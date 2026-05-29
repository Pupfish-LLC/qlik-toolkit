---
name: qlik-performance
description: "Performance optimization for Qlik Sense: memory optimization (field types, dual values, symbolic keys, data volume estimation), script load optimization (QVD optimized load rules, preceding LOAD, redundant disk reads), expression calculation optimization (Aggr nesting, set analysis complexity, pre-calculated flags), calculation conditions, data reduction techniques (load-time vs runtime), and profiling/diagnostic approaches. Load when optimizing reload time, reducing app memory footprint, speeding up a slow chart, choosing between load-time vs expression-time computation, evaluating Aggr() cardinality, or diagnosing why an app feels slow."
user-invocable: false
---

# Qlik Performance

## Overview

Qlik Sense stores all loaded data in RAM. Memory efficiency is the highest-leverage optimization lever—every byte of unnecessary data increases reload time, degrades user query response, and wastes cloud infrastructure costs. Performance optimization involves three parallel tracks: (1) memory footprint during load via field types, data reduction, and normalization; (2) reload speed via QVD optimized loads, preceding LOADs, and minimal disk reads; (3) query speed via expression optimization and pre-calculated fields. This skill teaches the decision frameworks and patterns for each. Profiling—measuring before optimizing—is essential; many intuitive "improvements" worsen performance.

---

## 1. Architecture-Level Decisions

Performance starts with app architecture, before any field-level optimization. The highest-leverage choices are whether to keep logic in a single app vs split into QVD generator/consumer or four-layer extract/transform/model/UI, and where incremental-load boundaries fall. These choices are driven by reload cycle time, memory pressure, and consumer count — not raw data volume alone.

### A. Volume, Refresh-Time, and Team-Structure Triggers

Qlik does not publish official thresholds for "this app is too big" or "this reload is too slow." The signals below are **practitioner heuristics**, calibrated against typical Qlik Cloud and Sense Enterprise deployments. They vary by environment, hardware, source connection speed, and dimension cardinality — treat them as starting points for evaluation, not hard limits.

| Signal | Practitioner Threshold | What It Implies |
|---|---|---|
| In-memory footprint | A few GB, well inside tenant/server RAM | Single app is sustainable |
| In-memory footprint | Approaching RAM budget per concurrent user | Memory pressure forces a split for headroom |
| Reload duration | Fits refresh SLA with margin | Current architecture is sustainable |
| Reload duration | Exceeds refresh SLA, or extract phase dominates | Decouple via QVD generator/consumer |
| Sources | Many, rate-limited, or slow | Generator app owns extraction; consumers stay decoupled |
| Consumer apps | Multiple apps sharing the same source data | Generator/consumer eliminates duplicate extract logic |
| Team ownership | Separate data-engineering and analytics teams | Four-layer split formalizes the ownership boundary |

Avoid framing reload thresholds in absolute minutes — the right number depends on whether the refresh SLA is "near-real-time" (minutes), "intraday" (hours), or "overnight" (multi-hour window). A 30-minute reload is fine overnight, problematic hourly.

Investigate field-level and script-load optimization before splitting. Architecture changes carry operational cost; spend it deliberately.

Structural mechanics for each pattern — generator/consumer contracts, four-layer contracts, binary load syntax — live in `qlik-data-modeling` → `multi-app-architecture.md`. This section covers WHEN to split based on performance signals; that file covers HOW the patterns work.

### B. Memory Budget at Design Time

Estimate per-layer memory before building. Document the estimate inline in script comments alongside the load step (see Section 2.F for the format). Headline rule: peak memory during load is typically larger than the final in-memory footprint (extract happens before filter; joins happen before drop), so size headroom for the peak, not the resting state.

---

## 2. Memory Optimization Fundamentals

Qlik's in-memory engine loads all data at reload time and keeps it resident. Memory efficiency is critical.

### A. Field Data Types and Memory Footprint

Qlik Sense stores every distinct value of each field exactly once in a per-field **symbol table**; data tables (fact + dimension) hold only compact bit-stuffed pointers into those symbol tables. This two-table model means memory cost depends on **cardinality** (number of distinct values), not row count, for the symbol-table portion — and on `ceil(log2(cardinality))` bits per row for the pointer portion.

Practical implications:
- Choose the narrowest type the value fits in. Integers, numerics, and short strings each have characteristic per-distinct-value costs (Qlik's official documentation does not publish exact byte numbers; published practitioner figures vary by version, but the ordering is stable: integer < numeric < short string < long string < dual).
- A 4-digit code stored as a string has higher per-distinct-value symbol-table cost than the same code stored as an integer. The fact-table pointer cost is the same in both cases (driven by cardinality, not type).
- For HIGH-CARDINALITY fields in LARGE fact tables, the pointer-bit savings can still matter: lower cardinality means fewer bits per pointer (e.g., 10K distinct values = 14 bits/row; 1M distinct = 20 bits/row).

Reference for the symbol-table / bit-stuffed-pointer concept: Henric Cronström, "Symbol Tables and Bit-Stuffed Pointers," Qlik Design Blog.

**Strategy:** Load dates as integers (days since epoch). Use expressions to format for display. Example:
```qlik
LOAD Date(date_field) AS [Date.Key]  // Integer, ~4 bytes per value
FROM [data.qvd] (qvd);
// In expression: Date(Floor([Date.Key]))  // Formats as YYYY-MM-DD on demand
```

### B. Dual Values

A Dual field stores both text (e.g., 'January') and numeric (e.g., 1). Used when BOTH representations are needed in the UI for sorting and display.

```qlik
Dual('January', 1) AS [Month]  // ~16-24 bytes vs. ~8 bytes for numeric alone
```

Dual values consume approximately 2x memory of a simple numeric field. Use Dual only when:
- The field is displayed as text in listboxes or charts (needs 'January', not '1')
- The field must sort numerically (month 1-12) despite text display

**Anti-pattern:** Creating unnecessary Dual fields for every dimension. A color field stored as Dual('Red', 1) wastes memory if it never appears in a sorted listbox.

### C. Symbolic Keys vs. Numeric Keys

String-based keys consume more memory than numeric keys because each distinct string takes more bytes in the symbol table than each distinct integer. The fact-table pointer cost is the same either way (driven by cardinality).

- `customer_id = 'CUST_12345'` — each distinct string is stored once in the customer_id symbol table; ~12+ bytes per distinct value
- `customer_id = 12345` — each distinct integer is stored once; ~4 bytes per distinct value

For a 1M-distinct-customer fact table with 100M rows: the savings is in the symbol table (~8 bytes × 1M = ~8MB), not in the data table (which uses ~20-bit pointers either way).

For large dimensions (>1M rows), converting natural string keys to sequential integers via `AutoNumber()` reduces memory significantly. For composite keys (multiple fields concatenated), use `AutoNumberHash128()`, which hashes the inputs before assigning a sequential integer — collision-safe AND integer-typed in one step. Tradeoff: improves memory, reduces debuggability.

Note: `Hash128()` alone returns a 22-character string (per Qlik help), so it does NOT reduce memory versus a typical string key. Use `Hash128()` for stable cross-reload hashing or PII masking, not for memory optimization.

```qlik
// WRONG for large tables: string keys repeated millions of times
[Customer]: LOAD customer_id, name FROM [customers.qvd] (qvd);

// RIGHT for large tables: sequential integer keys via AutoNumber
[Customer]:
LOAD AutoNumber(customer_id, 'CustomerKey') AS [Customer.Key], name
FROM [customers.qvd] (qvd);

// RIGHT for composite keys: AutoNumberHash128 in one step
[Order.Line]:
LOAD AutoNumberHash128(order_id, line_no, 'OrderLineKey') AS [OrderLine.Key], ...
FROM [order_lines.qvd] (qvd);
```

### D. Reducing Field Count

Every field consumes memory. In the raw/transform layer, load only fields needed downstream. Drop:
- Technical metadata: `load_datetime`, `source_system`, `revision_id`
- Deprecated fields no longer used by consumers
- Debugging columns from source systems

**Pattern:**
```qlik
// WRONG: Load all 50 source columns
[_Raw]: LOAD * FROM [db_export.csv];

// RIGHT: Load only 20 fields needed
[_Raw]:
LOAD order_id, product_id, customer_id, amount,
     order_date, region_code, status
FROM [db_export.csv];
```

Removing 30 unused fields may reduce memory footprint by 10-30% depending on data types and cardinality.

### E. Table Normalization vs. Denormalization

- **Normalized:** Separate dimension tables with one row per member. Fact tables contain only keys and measures. Memory efficient for large fact tables with repeated dimension values.
- **Denormalized:** Dimension attributes repeated in fact table rows. Simpler model, higher memory.

**Decision rule:** Default to normalized. Denormalize only if dimension cardinality is very low (<100 values) and the denormalized column is <50 bytes.

### F. Data Volume Estimation

Document expected row counts and field widths at each stage:
```qlik
// In script comments:
// Source: 100M transaction rows, ~80 bytes per row = 8GB raw
// After filter (last 24 months): 25M rows, 80 bytes = 2GB
// After normalization: Fact (25M × 20 bytes) + Customer Dim (500K × 200 bytes) = 0.6GB
// Expected final model: ~0.7GB in-memory
```

When memory pressure arises later, this history enables targeted reduction.

---

## 3. Script Load Optimization

Script performance directly impacts reload duration and peak memory during load.

### A. When to Optimize QVD Reads

Optimized QVD read is the highest-leverage reload-time lever. Practitioner figures: roughly an order of magnitude faster than standard QVD read, roughly two orders of magnitude faster than re-querying a database (Qlik does not publish exact numbers; ratios vary by data shape).

**Decision framework:**

| Situation | Decision |
|---|---|
| QVD read is the dominant phase of a slow reload | Optimize first — every other lever is smaller |
| Need to transform fields during the QVD load | Use a preceding LOAD: inner reads QVD optimized, outer transforms in-memory |
| Need to filter QVD rows by a key list | Use single-parameter `EXISTS(key_field)` — preserves optimization |
| Need to filter by a value range or expression | Accept standard read; the unpack cost is unavoidable for value-based filtering |
| Two-parameter `EXISTS(alias, field)` is needed for dedup | Accept standard read — or split: optimized load + resident dedup if QVD read dominates |
| Same QVD consumed by many maps | Load once to temp, build all maps RESIDENT, then DROP — one disk read per QVD per reload |

The full preservation/break rules with worked examples, the EXISTS single-vs-two-parameter mechanics, the preceding-LOAD-for-transforms pattern, and the load-once-map-many pattern are in `qlik-load-script` → `references/qvd-operations.md`. Apply the decisions above; consult the mechanics file when writing the actual LOAD statement.

### B. Temp Table Cleanup

Temporary tables (prefixed with `_`) consume memory throughout the reload. Every `_` table must be explicitly dropped after use.

```qlik
[_RawOrders]: LOAD * FROM [orders.qvd] (qvd);
// ... use _RawOrders to create downstream tables ...
DROP TABLE [_RawOrders];
// Frees memory immediately; peak memory reduced
```

The `qlik-review-checklist` skill (item P-2.3) flags missing `DROP TABLE` on any `_`-prefixed temp table.

### C. Narrow Before STORE

In QVD generator/consumer architectures, the generator's output width compounds across every consumer: ten extra fields in the generator means ten extra fields loaded into each consumer's memory. Narrow the in-memory table to a downstream-only field set before STORE. This reduces QVD file size, QVD read time for every consumer, and downstream memory footprint.

The mechanics — selecting fields with a RESIDENT load before STORE — are in `qlik-load-script` → `references/qvd-operations.md` (Narrow Before STORE).

---

## 4. Expression Calculation Optimization

Expressions execute during user interaction (sheet opens, selections made, filters changed). Inefficient expressions degrade sheet response time from <100ms (target) to >1000ms (unusable).

### A. Avoid Expensive Aggregation Patterns

**Nested Aggr():** Each `Aggr()` call creates internal temporary tables for each dimension value. Nested Aggr calls multiply temporary tables exponentially.

```qlik
// SLOW: Nested Aggr creates N² temporary tables
Sum(Aggr(Sum(sales) / Aggr(Count(distinct_product), product_id), product_id))
// N=100 products → 10,000 temporary tables per expression evaluation
```

**Fix:** Pre-calculate in the load script:
```qlik
// In load script:
LOAD product_id, Sum(sales) AS [Sales.Total], Count(Distinct order_id) AS [Orders.Count]
RESIDENT [Fact.Sales]
GROUP BY product_id;
// In expression: [Sales.Total] / [Orders.Count]
// Execution: immediate lookup, no aggregation
```

**Aggr() and dimension cardinality:** `Aggr()` creates a virtual table with one row per distinct combination of the specified dimensions in the current selection context. Cardinality is the primary performance driver: low-cardinality dimensions evaluate quickly; high-cardinality dimensions create massive virtual tables and slow evaluation noticeably.

```qlik
// Manageable: Aggr over a low-cardinality dimension
Aggr(Sum([Amount]), [Customer.Region])  // tens to hundreds of regions

// Slow: Aggr over a transaction-level key
Aggr(Sum([Amount]), [Transaction.ID])  // millions of distinct values → massive virtual table
```

Practitioner cardinality bands (not Qlik-published; vary by hardware, RAM, selection state):
- Up to roughly low-thousands of distinct values per dimension — Aggr() typically evaluates without noticeable delay.
- Beyond hundreds of thousands — Aggr() becomes a likely bottleneck; profile at typical selection states before relying on it in interactive contexts.

**Selection-context sensitivity:** the cardinality that matters is the cardinality *under the current selection*, not the field's total cardinality. The same `Aggr(Sum([Amount]), [Product.Key])` may evaluate quickly when a region is selected (filtering to ~1,000 products) and slowly with no selections (50,000+ products visible). Document this in catalog entries: "Performance varies with selection context; fastest with region or time-period selected."

**Mitigation when Aggr cardinality is unavoidable:**
- Pre-calculate the inner aggregation in the load script and reference the pre-computed field.
- Apply a calculation condition (Section 5) to suppress evaluation when too many values are visible.
- Combine with set analysis to constrain the cardinality before Aggr evaluates.

**Count(DISTINCT ...):** `Count(DISTINCT field)` evaluates over distinct values rather than rows. Qlik's official documentation on the Count function does not characterize it as slow. Treat it as a normal aggregation in most cases.

When to consider pre-calculation in the load script:
- The same distinct count is used across many charts (caching the value avoids repeated work)
- The expression is part of a larger `Aggr()` or set-analysis construct that is already a known bottleneck
- Profiling (App Performance Evaluation — see Section 7) shows the specific Count(DISTINCT) expression as a hotspot

Do NOT reflexively replace Count(DISTINCT) with a pre-calculated field. A load-script `Count(DISTINCT)` aggregates over a single grain and is not interchangeable with chart-context distinct counts, which respect user selections.

### B. Combine Modifiers Inside One Set Expression

Multiple field constraints belong inside a single `<...>` modifier, comma-separated. The valid set operators (`+`, `-`, `*`, `/`) combine whole set expressions for union/difference/intersection/symmetric-difference semantics — they are not a way to "chain" modifiers.

```qlik
// WRONG (fictional syntax — Qlik will not parse this):
{<Year = {">$(vMaxYear)"}>} {<Region = {"North"}>} {<Status = {"Active"}>}

// RIGHT: comma-separate modifiers inside one set
Sum({<Year = {">$(vMaxYear)"}, Region = {"North"}, Status = {"Active"}>} [Sales.Amount])
```

Each modifier inside `<...>` is evaluated once per cell context, so reducing modifier count and avoiding nested `P()`/`E()` element functions are the relevant performance levers — not "flattening levels," because levels don't exist in set syntax.

For union/difference of distinct selection states, use the set operators:

```qlik
// Union: sales for Year=2024 OR Region=North
Sum({<Year={2024}>} [Sales.Amount]) + Sum({<Region={"North"}>} [Sales.Amount])
```

### C. String Operations in Expressions

String functions (SubString, Len, Upper, Lower, Trim) are expensive at query time:
```qlik
// SLOW: Executed for every user selection
{<[Customer.Name] = {$(=Upper(vSelectedName))}>}

// FAST: Pre-calculate or pass the value
{<[Customer.Name] = {$(=vSelectedNameUpper)}>}
```

Pre-process strings at load time when possible.

### D. Calculation Weight Categorization

When documenting expressions in a catalog or reviewing performance, use a coarse calculation-weight bucket to flag attention. The categories are practitioner conventions, not Qlik-published metrics — they communicate relative cost to fellow developers, not absolute timing.

| Weight | Typical Pattern | Why |
|---|---|---|
| **Low** | Simple Sum/Count/Avg over indexed fields; field references; basic set modifiers on small fact tables | Single-pass aggregation; engine evaluates in tens of milliseconds for typical sizes |
| **Medium** | Set analysis with multiple modifiers; Count(DISTINCT) on high-cardinality fields; If() with simple branches; non-nested Aggr on low/medium-cardinality dimensions | Multiple passes or modifier evaluation; usually acceptable for interactive use |
| **High** | Nested Aggr; Aggr over high-cardinality dimensions; complex string operations at query time; Rank/RankMin/Top-N inside Aggr; recursive expressions | Virtual tables, repeated aggregation passes, or string work that should ideally be precomputed in the load script |

Label every catalog entry. High-weight expressions are the first place to look when sheet response time degrades, and the first candidates for pre-calculation in the load script or for calculation conditions that gate their evaluation.

This labeling is a documentation convention, not an enforced check. Actual cost depends on selection state, table sizes, and hardware. Treat the bucket as a hint for "where to look first," not as a measurement.

---

## 5. Calculation Conditions

Calculation conditions prevent expensive expression evaluation when the context doesn't support the calculation. Pair every condition with a message variable explaining why the calculation is suppressed.

### A. When to Use Calculation Conditions

- **Single-value dependency:** Expression requires exactly one selected value (e.g., comparing to a single customer's baseline)
- **Row threshold:** Visualization should only show when sufficient data is selected (e.g., ≥100 transactions)
- **Cardinality limit:** Expression degrades with high cardinality (e.g., word clouds, ranking queries)

### B. Calculation Condition Patterns

**Pattern 1: Single-value requirement**
```qlik
// In script:
SET vCondition_SingleCustomer = GetSelectedCount([Customer.ID]) = 1;
SET vMessage_SingleCustomer = 'Select exactly one customer to view comparison';

// In expression:
IF($(vCondition_SingleCustomer),
   Sum({<[Customer.ID] = {$(=Concat([Customer.ID]))}>} [Sales.Amount]),
   Null())

// In sheet: If expression returns NULL, display vMessage_SingleCustomer as text object
```

**Pattern 2: Row count threshold**
```qlik
// In script:
SET vCondition_MinRows = GetSelectedCount([Transaction.ID]) >= 100;
SET vMessage_MinRows = 'Select at least 100 transactions (current: $(=GetSelectedCount([Transaction.ID])))';

// In expression:
IF($(vCondition_MinRows),
   Aggr(Sum([Sales.Amount]), [Product.Category]),
   Null())
```

**Pattern 3: Cardinality check**
```qlik
// In script:
SET vCondition_LowCardinality = GetSelectedCount([Customer.ID]) <= 1000;
SET vMessage_LowCardinality = 'Select ≤1000 customers (too many to display ranking)';

// In expression (pseudo-code):
IF($(vCondition_LowCardinality),
   Aggr(Rank(Sum([Sales.Amount])), [Customer.ID]),
   Null())
```

---

## 6. Data Reduction Techniques

Reducing data volume at load time is always more efficient than filtering at query time.

### A. Load-Time Data Reduction (Most Efficient)

- **Date range limiting:** Load only recent history. `WHERE [Date.Key] >= $(vCutoffDate)`
- **Field removal:** Drop unused fields before STORE
- **Table narrowing:** Extract subsets for specific consumers
- **Aggregation at load:** Summarize to weekly/monthly if daily granularity is unnecessary
- **Section Access data reduction:** Filter by user role at load (most secure and efficient)

### B. Runtime Data Reduction (Less Efficient)

- **Set analysis filters:** `{<Region = {'North'}>}` evaluated at query time
- **Preceding LOAD with WHERE:** Multi-step source processing

**Decision rule:** Default to load-time. Use runtime filtering only when subset criteria cannot be known at load time.

---

## 7. Profiling and Diagnostic Approaches

Measure before optimizing. Qlik provides built-in tools.

### A. Document Analyzer

The Document Analyzer (Qlik Cloud) reports:
- Table row counts and memory footprint per table
- Field cardinality and data types
- Reload time breakdown
- Expression evaluation time

**Usage:** After reload, sort tables by memory footprint. Target largest tables for optimization.

### B. App Performance Evaluation

Qlik Cloud provides "Application performance evaluation" (sometimes called the App Performance Evaluator) for app-level diagnostics. Per Qlik help, it reports:
- Initial load time for public sheets
- Cached sheet load time
- Initial and cached object load time per sheet
- The top-5 slowest objects within each sheet

**What it does NOT do:** It reports at sheet and object level, not at individual-expression level. To attribute slowness to a specific expression, use the object-level breakdown combined with knowledge of which expressions back which objects.

**Usage:** Run the evaluation after representative reload + interaction. Target sheets and objects with load time >1s, then identify the contributing expression(s) for optimization.

Reference: https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_Hub/Apps/app-performance-evaluation.htm

### C. TRACE-Based Timing

Add markers at major phases:
```qlik
TRACE === EXTRACT: Starting orders QVD load ===;
[_Orders]: LOAD * FROM [orders.qvd] (qvd);
TRACE === EXTRACT: Completed. Rows: $(=NoOfRows('_Orders')), Time: $(Now()) ===;

TRACE === TRANSFORM: Filtering to last 24 months ===;
[Filtered.Orders]: LOAD * WHERE [Date.Key] >= $(vCutoffDate) RESIDENT [_Orders];
TRACE === TRANSFORM: Completed. Rows: $(=NoOfRows('Filtered.Orders')) ===;
```

Review TRACE output in reload log. Phases consuming >5% of reload time are optimization targets.

### D. Row Count Logging

Log row counts to understand data reduction:
```qlik
LET vRowsAfterExtract = NoOfRows('_RawOrders');
// ... filtering ...
LET vRowsAfterFilter = NoOfRows('_FilteredOrders');
LET vReductionPercent = (1 - vRowsAfterFilter / vRowsAfterExtract) * 100;

// Document in script comment:
// Reduction: $(vRowsAfterExtract) → $(vRowsAfterFilter) rows ($(vReductionPercent)% reduction)
```

---

## References

For detailed before/after optimization patterns with measurement approaches, code examples, and memory impact calculations, see `optimization-patterns.md` in this skill directory.
