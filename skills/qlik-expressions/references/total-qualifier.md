# TOTAL Qualifier Reference

Canonical home for the TOTAL qualifier: what it does, the field-list form, interaction with set analysis, the percentage-of-total pattern, the parsing trap with field names containing the word "Total", and failure modes. Companion to `qlik-expressions/SKILL.md` Section 3 (overview).

## 1. What TOTAL Does

TOTAL changes the **dimension scope** of an aggregation. Without TOTAL, an aggregation operates within the current chart cell's dimension context — `Sum([Amount])` in a row showing `Region=East, Year=2024` sums only amounts in that cell. With TOTAL, the aggregation disregards the chart dimensions and operates across all dimension values.

Per help.qlik.com — Defining the aggregation scope: TOTAL "disregards the dimensional value" and "the aggregation will instead be performed on all possible field values."

```
// Within-cell sum (default): respects chart dimensions
Sum([Amount])

// Across-all sum: ignores chart dimensions
Sum(TOTAL [Amount])
```

TOTAL is the right tool for **dimension-scope** problems (percentage of total, ratio to grand total). It is the wrong tool for **selection-scope** problems (exclude cancelled orders, only count active customers) — for those, use set analysis. The two solve different problems and are routinely confused.

## 2. TOTAL with a Field List

`TOTAL <FieldList>` inverts the default behavior: aggregation disregards **all** chart dimensions **except** those listed. Per tier 1: "the calculation is made disregarding all chart dimensions except those listed, that is, one value is returned for each combination of field values in the listed dimension fields."

```
// Chart dimensions: Year, Region
Sum(TOTAL [Amount])              // Grand total across all years and regions
Sum(TOTAL <Year> [Amount])       // Subtotal within each year (across all regions)
Sum(TOTAL <Year, Region> [Amount]) // Same as no TOTAL — redundant
```

**Rule:** The field list inside `<...>` must be a subset of the chart's dimensions. Listing a dimension that isn't on the chart silently produces unexpected behavior — the field doesn't exist as a chart dimension to "preserve" so the aggregation behaves as if TOTAL was used without a field list.

## 3. Percentage-of-Total Pattern

The canonical use case. Divide the dimensional value by the totalled value:

```
// Percentage of grand total
Sum([Amount]) / Sum(TOTAL [Amount])

// Percentage within region (assuming Region is a chart dimension)
Sum([Amount]) / Sum(TOTAL <Region> [Amount])
```

The numerator respects the cell's dimensions (Year, Region). The denominator ignores them (or preserves only Region in the second case). The ratio is the contribution percentage.

**Combine with a selection-preserving identifier when needed:**

```
Sum([Amount]) / Sum({$} TOTAL [Amount])
```

The `{$}` is the explicit current-selection set identifier (same as omitting it). Use it to make intent visible when reviewing or to explicitly contrast with `{1} TOTAL` (which would ignore all selections, not just dimensions).

## 4. TOTAL with Set Analysis

Set analysis and TOTAL combine. The set modifier appears first, then TOTAL, then the field. Per tier 1: combining them "overrides the selection and disregards all dimensions, except those listed within angle brackets after the TOTAL qualifier."

```
Sum({<Year={2024}>} TOTAL [Amount])               // 2024-only grand total
Sum({<Year={2024}>} TOTAL <Region> [Amount])      // 2024 subtotal per region
Sum({1} TOTAL [Amount])                            // All-data grand total (ignores selection)
```

**Order of evaluation:** the set filter applies first (restricting the data), then TOTAL aggregates across the filtered set with the dimension scope changed. TOTAL does not reset the set filter.

**Readability convention:** write `Sum({<...>} TOTAL <DimList> [Field])` in that order. The set modifier directly after the function, then TOTAL, then the optional dimension list, then the field. This is also the order tier-1 examples use.

## 5. The "Total" Field-Name Parsing Trap

`TOTAL` is a case-insensitive keyword. If the data model has a field whose name starts with the word "Total" (e.g., `Total Amount`, `Total Sales`), an expression like `Sum({<...>} Total Amount)` is parsed as `Sum({<...>} TOTAL Amount)` — the keyword TOTAL applied to a field named `Amount`. The intended field `Total Amount` is silently misinterpreted.

```
// AMBIGUOUS: Total is the TOTAL keyword; Amount is the field
Sum({<Year={2024}>} Total Amount)

// EXPLICIT: square brackets force literal field-name interpretation
Sum({<Year={2024}>} [Total Amount])
```

**Rule:** any field name beginning with "Total" (or "total", any case) must be wrapped in square brackets at every reference. When reviewing expressions, check whether `Total` before a field name is the TOTAL qualifier or part of the field name.

## 6. Performance Considerations

TOTAL forces aggregation across all dimension combinations, which can be a row-by-row scan if the engine cannot use cached subtotals. The performance impact scales with fact-table size and dimension cardinality.

- Tens of millions of rows with a few-dozen distinct dimension values: typically fine.
- Hundreds of millions of rows with high-cardinality dimensions: TOTAL adds noticeable cost; profile before relying on it in interactive contexts.
- Nested TOTAL expressions like `Sum(TOTAL x) / Sum(TOTAL y)` scan the data twice. Combine into a single ratio expression when possible.

**Mitigation when TOTAL is on a hot path:**
- Pre-calculate the totalled value in the load script as a derived field (e.g., a `Total.Amount` field equal to the grand total replicated on every row). Then `Sum([Amount]) / Max([Total.Amount])` avoids the runtime scan.
- Use a calculation condition (see `qlik-expressions/SKILL.md` Section 7) to suppress evaluation when too many values would be in scope.

See `qlik-performance` § 4 Expression Calculation Optimization for the calculation-weight bucket; TOTAL expressions are typically Medium weight, escalating to High on very large fact tables or with nested TOTAL.

## 7. Failure Modes

**Using TOTAL when set analysis is needed.** TOTAL changes dimension scope; set analysis changes selection scope. They are not interchangeable. A user asking "show me revenue excluding cancelled orders" needs set analysis (`Sum({<Order.Status-={'Cancelled'}>} [Amount])`), not TOTAL. Confusing the two produces an expression that looks plausible but answers the wrong question.

**Missing TOTAL when dividing by grand total.** `Sum([Amount]) / Sum([Amount])` returns 100% for every row, because both numerator and denominator are scoped to the same dimensional cell. The denominator must use TOTAL to produce the grand total: `Sum([Amount]) / Sum(TOTAL [Amount])`.

**TOTAL without set analysis in a filtered context produces "selection-applied grand total".** Users sometimes expect `Sum(TOTAL [Amount])` to mean "the all-time grand total" but it respects the current selection — only the chart dimensions are ignored, not the user's filter selections. Use `Sum({1} TOTAL [Amount])` to ignore all selections and produce the true all-time grand total.

**Field-list dimension missing from chart.** `Sum(TOTAL <Region> [Amount])` in a chart whose only dimension is Year produces unexpected results — Region is not a chart dimension to "preserve." If Region isn't a chart dimension, the field list is meaningless. Either add Region as a dimension or remove it from the TOTAL field list.

**The Total field-name parsing trap.** See Section 5 — silent misinterpretation of expressions referencing fields beginning with "Total".

## 8. Catalog Documentation Convention

When an expression uses TOTAL, document:
- **Why** TOTAL is needed (percentage-of-total, ratio to subtotal, etc.).
- **What dimension scope** the TOTAL produces — grand total, within-region, within-year-and-region.
- **Whether the chart's dimensions match** the TOTAL field list — if they don't, the expression won't behave as expected when used in other charts.

Example catalog entry note:
```
TOTAL Notes: Used for percentage-of-region calculation. Denominator
preserves Region (must be a chart dimension); ignores Year, Product,
and any other chart dimension. Will not behave correctly if used in
a chart that does not include Region as a dimension.
```

## Source Notes

- TOTAL semantics: help.qlik.com — Defining the aggregation scope (Sense on Windows, current build) — tier 1.
- TOTAL + set analysis combined behavior: same source, "Using set analysis with the TOTAL qualifier" section — tier 1.
- TOTAL field-list rule: same source — tier 1.
- Field-name parsing trap with "Total": observed pattern; tier-1 docs do not call it out explicitly, but it follows directly from the case-insensitive keyword resolution rule.
