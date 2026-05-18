---
name: qlik-performance
description: |
  Memory optimization (field types, dual values, symbolic keys, data volume estimation),
  script load optimization (QVD optimized load rules, preceding LOAD, redundant disk reads),
  expression calculation optimization (Aggr nesting, set analysis complexity, pre-calculated flags),
  calculation conditions, data reduction techniques (load-time vs runtime), and
  profiling/diagnostic approaches for Qlik Sense. Load when optimizing or reviewing
  performance-sensitive artifacts.
contexts:
  - data-architect (model memory decisions)
  - script-developer (script efficiency)
  - expression-developer (expression calculation speed)
  - qa-reviewer (performance validation)
triggers:
  - "memory optimization"
  - "QVD optimized load"
  - "expression performance"
  - "reload speed"
  - "calculation condition"
  - "data reduction"
  - "performance profiler"
  - "Aggr nesting"
  - "set analysis"
user-invocable: false
---

# Qlik Performance

## Overview

Qlik Sense stores all loaded data in RAM. Memory efficiency is the highest-leverage optimization lever—every byte of unnecessary data increases reload time, degrades user query response, and wastes cloud infrastructure costs. Performance optimization involves three parallel tracks: (1) memory footprint during load via field types, data reduction, and normalization; (2) reload speed via QVD optimized loads, preceding LOADs, and minimal disk reads; (3) query speed via expression optimization and pre-calculated fields. This skill teaches the decision frameworks and patterns for each. Profiling—measuring before optimizing—is essential; many intuitive "improvements" worsen performance.

---

## 1. Memory Optimization Fundamentals

Qlik's in-memory engine loads all data at reload time and keeps it resident. Memory efficiency is critical.

### A. Field Data Types and Memory Footprint

Qlik supports integer, numeric, and string data types. Choose the narrowest type that holds the value:

- **Integer:** ~4-8 bytes per value (depending on range). Use for IDs, dates, counts. Integer fields compress well in QVD files.
- **Numeric (floating-point):** ~8 bytes. Use for amounts, percentages, measurements. Less compressible than integers.
- **String:** Full character length plus ~10-20 bytes overhead. Use only when necessary (names, descriptions, codes).
- **Implicit conversion:** If you load a 4-digit code as a string, it consumes 14+ bytes per value. As an integer, it consumes 4 bytes. For 100M rows, this is 1GB difference.

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

String-based keys consume significantly more memory than numeric keys:
- `customer_id = 'CUST_12345'` (13+ bytes per value)
- `customer_id = 12345` (4 bytes per value)

For large dimensions (>1M rows), mapping natural string keys to numeric via `AutoNumber()` or `Hash128()` reduces memory. Tradeoff: improves memory, reduces debuggability.

```qlik
// WRONG for large tables: string keys repeated millions of times
[Customer]: LOAD customer_id, name FROM [customers.qvd] (qvd);

// RIGHT for large tables: numeric keys
[Customer]:
LOAD Hash128(customer_id) AS [Customer.Key], name
FROM [customers.qvd] (qvd);
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

## 2. Script Load Optimization

Script performance directly impacts reload duration and peak memory during load.

### A. QVD Optimized Load Rules

A "QVD optimized load" allows Qlik to skip decompression and deserialization—reading QVD blocks directly into memory. Optimized loads are ~100x faster than database reads and ~10x faster than standard QVD reads.

**Requirements for optimized load (ALL must be met):**
1. No transformations on any field (no expressions, no type conversions)
2. No field reordering
3. No field renaming
4. No WHERE clause filtering (except one rare exception; see below)
5. No field subset (all fields must be loaded)
6. No Map() function calls on fields

**What breaks optimized load:**
- Adding a derived field: `Num(id_field) AS id` breaks it
- Filtering rows: `WHERE date_field >= '2024-01-01'` breaks it
- Renaming: `customer_id AS [Customer.Key]` breaks it (despite alias being allowed in some documentation, safest to avoid for optimized read)
- Reordering fields from QVD order
- Any function call on any field

**One exception that preserves optimized load:**
```qlik
// This pattern does NOT break optimized load:
[Result]: LOAD * FROM [file.qvd] (qvd) WHERE EXISTS(qvd_hash_field, $1);
```
Uses a pre-calculated hash in the QVD and validates against a hash set. Rare pattern. Document if used.

**Pattern for optimized load:**
```qlik
// Optimized: No transformations, no filtering, no reordering
[Dimension.Customer]:
LOAD * FROM [lib://QVDs/Customer.qvd] (qvd);
// Expected reload time: <100ms for 100M rows
```

**Pattern for transformations with preceding LOAD:**
When you need transformations, load to temp optimized, then apply transformations in-memory via Preceding LOAD:
```qlik
[Dimension.Customer]:
LOAD *, Upper([Customer.Name]) AS [Customer.Name];
LOAD * FROM [lib://QVDs/Customer.qvd] (qvd);
// Inner load is optimized (~100ms), outer transformation adds ~50ms
```

### B. Redundant Disk Reads

**Anti-pattern:** Loading the same QVD file twice.
```qlik
// WRONG: Reads product.qvd from disk twice
[Map_ProductName]: MAPPING LOAD product_id, product_name
FROM [lib://QVDs/Product.qvd] (qvd);
[Map_ProductCategory]: MAPPING LOAD product_id, product_category
FROM [lib://QVDs/Product.qvd] (qvd);
// Reload time: 2x the disk read time
```

**Right pattern:** Load once to temp, create multiple maps from resident:
```qlik
[_ProductTemp]: LOAD * FROM [lib://QVDs/Product.qvd] (qvd);
[Map_ProductName]: MAPPING LOAD product_id, product_name RESIDENT [_ProductTemp];
[Map_ProductCategory]: MAPPING LOAD product_id, product_category RESIDENT [_ProductTemp];
DROP TABLE [_ProductTemp];
// Reload time: 1x the disk read time (no redundant QVD read)
```

**Rule:** Every QVD should be read from disk **exactly once** in the reload script.

### C. Temp Table Cleanup

Temporary tables (prefixed with `_`) consume memory throughout the reload. Every `_` table must be explicitly dropped after use.

```qlik
[_RawOrders]: LOAD * FROM [orders.qvd] (qvd);
// ... use _RawOrders to create downstream tables ...
DROP TABLE [_RawOrders];
// Frees memory immediately; peak memory reduced
```

The qlik-review.md checklist requires: every `_` table must have a corresponding `DROP TABLE` before reload completes.

### D. STORE Optimization

When writing QVD files, avoid storing entire tables if only a subset is needed downstream. Narrow before storing:
```qlik
// WRONG: Stores all 20 fields (8 bytes overhead each)
STORE [_AllOrderData] INTO [orders_all.qvd];

// RIGHT: Load only needed fields, then store
[_OrdersSubset]:
LOAD order_id, order_date, customer_id, amount, region
RESIDENT [_AllOrderData];
STORE [_OrdersSubset] INTO [orders.qvd];
DROP TABLE [_OrdersSubset];
```

Narrowing before STORE reduces:
- QVD file size (less disk usage)
- QVD load time (fewer fields to decompress)
- Downstream memory footprint

---

## 3. Expression Calculation Optimization

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

**Count(DISTINCT ...):** `Count(DISTINCT field)` is computationally expensive; Qlik evaluates all distinct values.
```qlik
// SLOW in expression (evaluated for every cell):
Count(DISTINCT [Customer.ID])

// FAST: Pre-calculated in load:
// In load script: Count(Distinct customer_id) AS [Customers.Count]
// In expression: [Customers.Count]
```

### B. Complex Set Analysis Nesting

Set analysis with nested conditions evaluates the set for every cell. Limit nesting:
```qlik
// SLOW: 3-level nesting
{<Year = {">$(vMaxYear)"}>} with {<Region = {"North"}>} with {<Status = {"Active"}>}

// FAST: Flatten to 2 levels or use pre-calculated flags
{<Year = {">$(vMaxYear)"}, Region = {"North"}, Status = {"Active"}>}
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

---

## 4. Calculation Conditions

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

## 5. Data Reduction Techniques

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

## 6. Profiling and Diagnostic Approaches

Measure before optimizing. Qlik provides built-in tools.

### A. Document Analyzer

The Document Analyzer (Qlik Cloud) reports:
- Table row counts and memory footprint per table
- Field cardinality and data types
- Reload time breakdown
- Expression evaluation time

**Usage:** After reload, sort tables by memory footprint. Target largest tables for optimization.

### B. Performance Profiler

Qlik Cloud includes a Performance Profiler for sheet-level diagnostics:
- Identifies slow expressions by name and execution time
- Shows which selections trigger expensive recalculations

**Usage:** Make a selection that triggers slowness, inspect expression times. Target >200ms expressions for optimization.

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
