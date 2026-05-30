# Aggr() Patterns Reference

Canonical home for the `Aggr()` function: what it does, the virtual-table mental model, multi-dimension grouping, NODISTINCT semantics, interaction with set analysis, the calculated-dimension restriction, the dimension-vs-measure distinction, and failure modes. Cardinality and performance bands live in `qlik-performance` § 4.A — pull from there when documenting selection-context sensitivity.

Companion to `qlik-expressions/SKILL.md` Section 4 (overview).

## 1. What Aggr() Does

`Aggr()` evaluates an inner aggregation once per distinct combination of the specified dimension values, returning an **array of values** (one per dimension combination). Per help.qlik.com — Aggr function: it "returns an array of values for the expression calculated over the stated dimension or dimensions." The result "can be compared to creating a temporary staged result set (a virtual table), over which another aggregation can be made."

```
// Virtual table: one row per Customer, with that customer's total amount
Aggr(Sum([Amount]), [Customer.Key])

// Outer aggregation operates on the array
Avg(Aggr(Sum([Amount]), [Customer.Key]))    // Average customer amount
Max(Aggr(Sum([Amount]), [Customer.Key]))    // Highest customer amount
Count(Aggr(Sum([Amount]), [Customer.Key]))  // How many customers have any amount
```

**Mental model:** picture a hidden two-column table — dimension on the left, inner-aggregation result on the right. The outer aggregation walks that hidden table.

## 2. Syntax

```
Aggr({SetExpression} [DISTINCT | NODISTINCT] expr, StructuredParameter [, StructuredParameter ...])
```

- `{SetExpression}` — optional set analysis applied at the Aggr level. Sets the record scope before the inner aggregation evaluates.
- `DISTINCT` (default) — one return value per distinct dimension combination.
- `NODISTINCT` — one return value per source-row combination; preserves duplicates from the underlying data.
- `expr` — the inner aggregation (e.g., `Sum([Amount])`, `Count(DISTINCT [Order.Key])`).
- `StructuredParameter` — a dimension. Multiple dimensions create combinations.

## 3. Why Aggr() Is the Only Valid Nested-Aggregation Mechanism

Direct nesting of aggregation functions is structurally invalid in Qlik. The engine cannot resolve two aggregation scopes simultaneously without an explicit intermediate step:

```
// INVALID — engine cannot resolve nested aggregation scopes
Avg(Sum([Amount]))
Sum(Count([Order.Key]))

// VALID — Aggr() materializes the inner aggregation as an intermediate virtual table
Avg(Aggr(Sum([Amount]), [Customer.Key]))
Sum(Aggr(Count([Order.Key]), [Customer.Key]))
```

Per tier 1: an inner aggregation in Aggr "should be enclosed in an outer aggregation function, using the array of results from the Aggr function as input to the aggregation in which it is nested." The TOTAL qualifier is the one documented exception that allows inner aggregation without Aggr — but that pattern aggregates across the whole table, not by dimension.

**The hidden-nesting trap via dollar-sign expansion.** If a SET variable contains an aggregation, placing `$(vMySum)` inside another aggregation expands to the invalid nested form at render time:

```
SET vRevenue = Sum([Amount]);
// Looks fine:
Avg($(vRevenue))
// Expands to (invalid):
Avg(Sum([Amount]))
```

Always use Aggr() as the intermediate step. If the variable is meant for nested-aggregation use, define a measure that wraps the Aggr: `SET vAvgCustomerRevenue = Avg(Aggr(Sum([Amount]), [Customer.Key]));`.

## 4. Multiple Dimensions

Listing multiple dimensions creates one row per distinct combination — a time-series bucket, a region-by-year breakdown, a customer-by-product matrix:

```
// Year-Month buckets
Aggr(Sum([Amount]), [Year], [Month])

// Customer-Product matrix
Aggr(Sum([Amount]), [Customer.Key], [Product.Key])

// Nested outer aggregation
Max(Aggr(Sum([Amount]), [Year], [Month]))  // Biggest monthly amount
```

Cardinality of the result is the **product** of the dimensions' cardinalities under the current selection. Two dimensions with 1,000 distinct values each produce up to 1,000,000 virtual rows. The qlik-performance § Aggr() and dimension cardinality section covers the selection-context sensitivity and mitigation patterns.

## 5. DISTINCT vs NODISTINCT

Default (DISTINCT) collapses to one row per dimension combination. NODISTINCT preserves the underlying row multiplicity. Per tier 1: with NODISTINCT, "each combination of dimension values may generate more than one return value, depending on underlying data structure."

```
// Default DISTINCT: one row per customer
Aggr(Sum([Amount]), [Customer.Key])

// NODISTINCT: one row per source-table row (rarely needed)
Aggr(NODISTINCT Sum([Amount]), [Customer.Key])
```

NODISTINCT is rare in practice — most use cases want distinct-dimension semantics. Use it only when the outer aggregation needs to count or weight by source-row multiplicity.

## 6. Aggr() with Set Analysis

Two positions for set modifiers. Both filter the record set the Aggr operation iterates over:

**Set inside the inner aggregation** (most common, recommended idiom):

```
Aggr(Sum({<Status={'Active'}>} [Amount]), [Customer.Key])
```

**Set at the Aggr level** (using the optional SetExpression parameter):

```
Aggr({<Status={'Active'}>} Sum([Amount]), [Customer.Key])
```

Per help.qlik.com — Aggr function: "By default, the aggregation function will aggregate over the set of possible records defined by the selection. An alternative set of records can be defined by a set analysis expression." The dimension iteration in either form walks the distinct dimension values present in the post-filter record set — customers with no Active rows do not appear in either virtual table because the filter is applied before grouping.

Prefer the inner-set form as the canonical style. It keeps the set scope visually adjacent to the aggregation it modifies and is the form most readers expect. Reach for the outer-set form only when a single set expression needs to govern multiple inner aggregations consistently, or when matching an existing convention in the codebase.

**Combined with TOTAL on the outer aggregation:**

```
Avg(Aggr(Sum([Amount]), [Customer.Key])) / 
  Sum(TOTAL Aggr(Sum([Amount]), [Customer.Key]))
```

The outer TOTAL ignores the chart's dimension scope; the inner Aggr defines what gets averaged or summed. Combining these is legal but should be reviewed carefully — most "share of customer average" expressions can be simplified.

## 7. Dimensions Must Be Single Fields

Per tier 1: "Each dimension in an Aggr() function must be a single field, and cannot be an expression (calculated dimension)."

```
// INVALID — calculated dimension inside Aggr
Aggr(Sum([Amount]), [Year] & [Month])

// VALID — pre-build the composite field in the load script, then use as dimension
// In script:
LOAD *, [Year] & '-' & [Month] AS [YearMonth] FROM ...;
// In expression:
Aggr(Sum([Amount]), [YearMonth])

// VALID — use multiple dimensions instead of a calculated combination
Aggr(Sum([Amount]), [Year], [Month])
```

The engine does not raise a clear error for calculated dimensions inside Aggr — symptoms include unexpected NULL results, wrong cardinality, or apparently random aggregation. When debugging "my Aggr returned something weird," check first whether the dimension argument is a single field reference.

## 8. Aggr() Result Is a Measure, Not a Dimension

`Aggr(...)` produces an array of values. It is a **measure expression**, not a field. It cannot be dropped directly into a chart's Dimensions panel and used as if it were a field.

```
// INVALID — Aggr cannot be used directly as a chart dimension
Chart dimension: Aggr(Sum([Amount]), [Customer.Key])

// VALID approach 1 — wrap in a calculated dimension that returns a field-like value
Chart dimension: =Aggr(Only([Customer.Region]), [Customer.Key])
// (Only() returns a single value per customer; the calculated dimension
//  evaluates to a list of customer regions — but this is unusual.)

// VALID approach 2 — pre-calculate in the script and use the resulting field
// In script:
LOAD [Customer.Key], 
    IF(Sum([Amount]) > 10000, 'High', 'Low') AS [Customer.ValueTier]
GROUP BY [Customer.Key]
RESIDENT [Fact];
// In chart dimension: [Customer.ValueTier]
```

When the dimension you want depends on an aggregation, pre-build it in the load script. Calculated dimensions using Aggr at chart time are expensive and brittle.

## 9. Failure Modes

**Treating Aggr as a "sum across all rows regardless of selection" override.** `Aggr(Sum([Amount]), [Customer.Key])` respects the current selection — the inner Sum sees only selected rows, and the dimension iteration covers only customers visible under the current selection. To override the selection, use explicit set analysis: `Aggr(Sum({1} [Amount]), [Customer.Key])` operates on all data, ignoring selections.

**Nested Aggr().** `Aggr(Aggr(...), ...)` compounds the virtual-table memory cost and is rarely the right answer. Common symptoms of mistaken nesting: extreme slowness, evaluation timeouts, or wrong results. If nested Aggr seems necessary, the load script is usually the better place to pre-compute the inner result. Document explicitly when nested Aggr is intentional.

**Forgetting Aggr's result is an expression, not a field.** See Section 8 — using Aggr directly in a chart's Dimension panel produces calculated-dimension behavior at high cost. If a dimension depends on aggregated data, pre-build it in the script.

**Calculated dimension inside Aggr.** See Section 7 — silent misbehavior. Pre-build composite fields in the script or pass multiple dimensions to Aggr.

**Set analysis position.** Inner-set and outer-set positions both filter the record set the Aggr iterates over (Section 6). Prefer the inner-set form as the canonical style; reach for the outer-set SetExpression parameter only when a single set must govern multiple inner aggregations or to match an existing convention.

**Hidden nesting via dollar-sign expansion.** See Section 3 — a SET variable containing an aggregation expands inside another aggregation to invalid nested form. Define wrapper measures that include the Aggr explicitly.

## 10. Catalog Documentation Convention

When an expression uses Aggr(), document:
- **Inner aggregation** (Sum, Count(DISTINCT), Max, etc.).
- **Dimension** of the virtual table — and whether it is a chart dimension or independent.
- **Set position** if the expression uses set analysis (inside the inner aggregation vs at the Aggr level).
- **Outer aggregation context** — what the Aggr's array feeds into.
- **Selection-context sensitivity** — note when the expression is fast under common selections and slow with no selections. See `qlik-performance` § 4.A for the cardinality bands and `qlik-performance` § 4.D for the Low/Medium/High calculation-weight labeling.

Example catalog entry note:
```
Aggr Notes: Inner aggregation Sum([Amount]) grouped by [Customer.Key].
Outer aggregation Avg() produces the average per-customer revenue.
Set analysis at inner-aggregation level (Active customers only). 
Performance varies with selection: fast with region selected (~10k 
customers visible), slow with no selections (300k customers). Calculation 
weight: Medium typical, High under no selections.
```

## Source Notes

- `Aggr()` semantics, virtual-table model, NODISTINCT, calculated-dimension restriction, SetExpression parameter: help.qlik.com — Aggr function (Sense on Windows, current build) — tier 1.
- Nested-aggregation rule: same source — tier 1.
- TOTAL exception for inner aggregation: help.qlik.com — Defining the aggregation scope — tier 1.
- Cardinality bands and selection-context sensitivity: practitioner heuristics; see `qlik-performance` § 4.A.
