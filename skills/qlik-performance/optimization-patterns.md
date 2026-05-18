# Performance Optimization Patterns

Detailed before/after optimization patterns with memory impact measurements and execution timing approaches.

---

## Pattern 1: Field Type Optimization — String to Integer

**Scenario:**
A product dimension loads product codes as strings ('PROD_00001', 'PROD_00002', ..., 'PROD_99999'). With 1M products and repeated in fact tables (order items, shipments, returns), this string duplication consumes significant memory.

**Before (String Keys):**
```qlik
[Dimension.Product]:
LOAD product_code AS [Product.Key],
     product_name AS [Product.Name],
     category AS [Product.Category]
FROM [products.csv];

[Fact.OrderItem]:
LOAD order_id AS [Order.Key],
     product_code AS [Product.Key],  // STRING: 'PROD_00001' is 11 bytes × 10M rows = 110MB
     quantity AS [Item.Quantity],
     amount AS [Item.Amount]
FROM [order_items.csv];
```

**Memory analysis:**
- Product dimension: 1M rows × (11 bytes + 50 bytes name + 20 bytes category) ≈ 81MB
- Fact table: 10M rows × 11 bytes (product_code) ≈ 110MB
- Total: ~191MB just for product keys

**After (Numeric Keys):**
```qlik
// Create a mapping of product_code to numeric ID
[_ProductMapping]:
LOAD product_code AS [Product.Code],
     AutoNumber(RowNo()) AS [Product.ID]
FROM [products_unique.csv];
[Map_ProductID]: MAPPING LOAD [Product.Code], [Product.ID] FROM [_ProductMapping];

// Load dimension using numeric key
[Dimension.Product]:
LOAD ApplyMap('Map_ProductID', product_code) AS [Product.Key],
     product_name AS [Product.Name],
     category AS [Product.Category]
FROM [products.csv];

// Load fact using numeric key
[Fact.OrderItem]:
LOAD order_id AS [Order.Key],
     ApplyMap('Map_ProductID', product_code) AS [Product.Key],  // NUMERIC: 1-999999 is 4 bytes × 10M = 40MB
     quantity AS [Item.Quantity],
     amount AS [Item.Amount]
FROM [order_items.csv];

DROP TABLE [_ProductMapping];
```

**Memory analysis (after):**
- Product dimension: 1M rows × (4 bytes + 50 bytes name + 20 bytes category) ≈ 74MB (7MB saved)
- Fact table: 10M rows × 4 bytes (product_id) ≈ 40MB (70MB saved)
- Total: ~114MB (77MB saved, 40% reduction in key-related memory)

**Tradeoff:**
- Improves: Memory by 40%, QVD file size by 40%, reload time (smaller files to decompress)
- Hurts: Debuggability (product code hidden behind numeric ID)

**When to use:** Large dimensions (>1M rows) or large fact tables with many key references. Skip for small lookup tables where memory savings are negligible.

**Reload timing:**
- Before: 5 seconds (product CSV parse + string key storage)
- After: 4.2 seconds (CSV parse + ApplyMap + numeric storage; mapping overhead minimal)
- Savings: ~800ms per reload

---

## Pattern 2: QVD Optimized Load vs. Standard Read

**Scenario:**
A customer dimension loaded from a large QVD file with 5M rows.

**Before (Standard Read with Transformations):**
```qlik
[Dimension.Customer]:
LOAD customer_id AS [Customer.Key],
     Upper(customer_name) AS [Customer.Name],  // TRANSFORMATION: breaks optimized load
     Lower(email) AS [Customer.Email],          // TRANSFORMATION: breaks optimized load
     birthdate AS [Customer.BirthDate]
FROM [lib://QVDs/customer_raw.qvd] (qvd);
```

**Reload timing:**
- QVD decompression: 1200ms
- Deserialization: 800ms
- Transformation (Upper/Lower): 600ms
- Total load time: ~2600ms

**After (Optimized Load + Preceding LOAD):**
```qlik
[Dimension.Customer]:
LOAD *, Upper([Customer.Name]) AS [Customer.Name],
       Lower([Customer.Email]) AS [Customer.Email];
LOAD customer_id AS [Customer.Key],
     customer_name AS [Customer.Name],
     email AS [Customer.Email],
     birthdate AS [Customer.BirthDate]
FROM [lib://QVDs/customer_raw.qvd] (qvd);
```

**Reload timing:**
- Inner LOAD (optimized): 800ms (QVD block read, no decompression)
- Outer LOAD (transformations): 400ms (in-memory Upper/Lower on 5M rows)
- Total load time: ~1200ms

**Performance improvement:**
- 54% faster reload (2600ms → 1200ms)
- Memory usage during load: ~200MB less (inner load decompresses once, outer load transforms in-place)

**Key insight:** Optimized load speed (800ms) >> standard read + deserialization (2000ms). Even a preceding LOAD with transformations (400ms) is worth the trade.

---

## Pattern 3: Redundant Disk Reads Elimination

**Scenario:**
Building multiple mapping tables from the same source. Without optimization, the source QVD is read multiple times.

**Before (Redundant Reads):**
```qlik
// First mapping: reads category.qvd
[Map_CategoryName]: MAPPING LOAD category_id, category_name
FROM [lib://QVDs/category.qvd] (qvd);

// Second mapping: reads category.qvd AGAIN
[Map_CategoryColor]: MAPPING LOAD category_id, category_color
FROM [lib://QVDs/category.qvd] (qvd);

// Third mapping: reads category.qvd AGAIN
[Map_CategoryHierarchy]: MAPPING LOAD category_id, parent_category_id
FROM [lib://QVDs/category.qvd] (qvd);
```

**Reload timing (large category.qvd, 50K rows):**
- QVD read 1: 200ms
- QVD read 2: 200ms
- QVD read 3: 200ms
- Total: ~600ms

**After (Single Read to Temp):**
```qlik
[_CategoryTemp]: LOAD * FROM [lib://QVDs/category.qvd] (qvd);

[Map_CategoryName]: MAPPING LOAD category_id, category_name RESIDENT [_CategoryTemp];
[Map_CategoryColor]: MAPPING LOAD category_id, category_color RESIDENT [_CategoryTemp];
[Map_CategoryHierarchy]: MAPPING LOAD category_id, parent_category_id RESIDENT [_CategoryTemp];

DROP TABLE [_CategoryTemp];
```

**Reload timing:**
- QVD read: 200ms (optimized, once)
- Resident mapping 1: 5ms
- Resident mapping 2: 5ms
- Resident mapping 3: 5ms
- Drop temp: 2ms
- Total: ~217ms

**Performance improvement:**
- 64% faster (600ms → 217ms)
- No additional memory overhead (temp table dropped immediately)

**Rule:** One disk read per QVD file. Create all derived maps from resident tables.

---

## Pattern 4: Dual Value Optimization

**Scenario:**
A month dimension where months must display as text ('January', 'February') but sort numerically (1, 2, ..., 12).

**Before (Unnecessary Dual):**
```qlik
[Dimension.Month]:
LOAD month_number AS [Month.ID],
     Dual(month_name, month_number) AS [Month.Name]  // All 12 rows use Dual: 12 × 16 bytes = 192 bytes
FROM [months.csv];
```

**After (Optimized):**
```qlik
[Dimension.Month]:
LOAD month_number AS [Month.ID],
     month_name AS [Month.Name]  // Simple string: 12 × 10 bytes = 120 bytes
FROM [months.csv];

// Sorting handled via HideSuffix in naming conventions, or via sort expression in chart properties
```

**Memory impact:**
- Dual field: 192 bytes (for 12-row dimension, negligible)
- String field: 120 bytes

**Tradeoff (this example):** For a 12-row dimension, Dual vs. string makes no practical difference. Use string; simpler to debug.

**When Dual matters:**
- High-cardinality dimensions with repeated lookups (10M+ rows in fact tables)
- Example: 1M distinct day-of-week + day-names. Using Dual('Monday', 2) × 1M rows = 16MB vs. 8MB without Dual

---

## Pattern 5: Calculation Condition to Avoid Expensive Aggregations

**Scenario:**
A dashboard chart showing top 20 products by sales volume. The visualization uses nested Aggr() to rank and filter. Without a calculation condition, the expression evaluates even with no selections, consuming CPU.

**Before (No Calculation Condition):**
```qlik
// Expression (slow):
Aggr(Rank(Sum([Sales.Amount])), [Product.Key])

// This evaluates for every chart dimension value, even with empty selections.
// With 10,000 products, evaluation creates 10,000 temporary tables.
// Response time: 1200ms
```

**After (With Calculation Condition):**
```qlik
// In script:
SET vCondition_MinProducts = GetSelectedCount([Product.Key]) <= 100;
SET vMessage_MinProducts = 'Select ≤100 products to view ranking (current: $(=GetSelectedCount([Product.Key])))';

// In expression:
IF($(vCondition_MinProducts),
   Aggr(Rank(Sum([Sales.Amount])), [Product.Key]),
   Null())
```

**Impact:**
- If user selects >100 products: Expression returns NULL immediately (no Aggr evaluation)
- If user selects ≤100 products: Expression evaluates (manageable overhead with 100 vs. 10,000)
- Response time: 50ms (condition check) vs. 1200ms (full aggregation)

**UX improvement:**
- Sheet shows: null (no data)
- Text object displays: "Select ≤100 products to view ranking (current: 5,000)"
- User understands why the chart is empty

---

## Pattern 6: Pre-Calculated Flags vs. Runtime Expressions

**Scenario:**
An order detail fact table with 100M rows. Expressions flag orders as "high-value" (>$10,000) or "bulk-order" (>100 items).

**Before (Runtime Calculation):**
```qlik
// In expression (evaluated per cell):
IF(Sum([Order.Amount]) > 10000, 'High-Value', 'Standard')

// For a chart with 1,000 dimension values (customers), evaluated 1,000 times:
// IF() check × 1,000 = 1,000 comparison operations per chart interaction
// Response time: 800ms
```

**After (Pre-Calculated Flag):**
```qlik
// In load script:
LOAD order_id AS [Order.Key],
     ...other fields...,
     IF(amount > 10000, 'High-Value', 'Standard') AS [Order.ValueCategory],
     IF(quantity > 100, 'Bulk', 'Regular') AS [Order.VolumeCategory]
RESIDENT [_RawOrders];

// In expression (simple lookup):
[Order.ValueCategory]

// Response time: 50ms (field reference only, no comparison)
```

**Memory tradeoff:**
- Adds 2 fields to fact table (20 bytes each): 100M rows × 20 bytes = 2GB
- Memory impact: ~2GB additional (assuming original fact table is ~10GB)
- Reload time: +200ms (IF() evaluation on 100M rows at load)
- Query time: -750ms per selection (eliminates runtime IF evaluation)

**ROI:** 2GB extra memory + 200ms reload time for 10+ sheets using the flag = net positive if users interact with dashboards daily (query time savings accumulate).

---

## Pattern 7: Data Volume Estimation and Documentation

**Scenario:**
A manufacturing dashboard loading transaction data. Script needs to estimate memory footprint to identify optimization opportunities.

**Documentation Pattern:**
```qlik
// ===== DATA VOLUME ESTIMATION =====
// Source: ERP extract from [lib://ERP/transactions.csv]
// Source records: ~150M transaction rows, ~150 bytes per row = 22.5GB raw

// Stage 1: Extract (Raw QVD)
// Load all 150M rows as-is, store Raw_Transactions.qvd
// Post-load: 150M rows, 150 bytes/row = 22.5GB (baseline)

// Stage 2: Transform
// Filter to last 36 months (90M rows, 40% reduction)
// Drop fields: audit_timestamp, revision_id, temp_staging_id (40 bytes)
// Post-transform: 90M rows, 110 bytes/row = 9.9GB

// Stage 3: Model
// Denormalize to fact + dimension join
// Fact: 90M rows × 60 bytes (measure + keys) = 5.4GB
// Customer Dim: 5M rows × 200 bytes = 1GB
// Product Dim: 50K rows × 150 bytes = 7.5MB
// Store Dim: 1K rows × 100 bytes = 100KB
// Total: ~6.5GB in-memory

// Expected reload: 45 seconds
// - Extract phase: 15 seconds (read + filter + STORE)
// - Transform phase: 20 seconds (aggregate, deduplicate)
// - Model phase: 10 seconds (QVD optimized loads + join + STORE)

// Peak memory during load: ~15GB (extract all 150M rows before filtering)
// Final model in-memory: ~6.5GB

TRACE === DATA VOLUME ESTIMATION ===;
TRACE Source records: 150M;
TRACE After filter (36 months): $(=NoOfRows('_Filtered')) rows;
TRACE Reduction: $(=Round((1 - NoOfRows('_Filtered') / 150000000) * 100, 2))%%;
```

**Benefits:**
- When users report memory/performance issues, developer can reference this documentation
- Enables targeted optimization: "Remove customer segment field (80 bytes × 90M = 7.2GB savings)"
- Justifies multi-app architecture: "Model exceeds single-server memory; split into regional apps"

---

## Pattern 8: Expression Profiling Template

**Scenario:**
Dashboard shows slow response when users select a date range. Developer needs to identify which expressions are slow.

**Profiling Pattern:**
```qlik
// In a temporary debug section (comment out before production):

[_ExpressionTest]:
LOAD *,
     Sum([Sales.Amount]) AS debug_simple_sum,
     Sum({<Year = {2024}>} [Sales.Amount]) AS debug_set_analysis,
     Aggr(Sum([Sales.Amount]), [Customer.ID]) AS debug_aggr_customer,
     Aggr(Rank(Sum([Sales.Amount])), [Product.Category]) AS debug_aggr_rank
RESIDENT [Fact.Sales];

// Reload with this debug section active
// Review reload log TRACE timing:
//   - If [_ExpressionTest] load takes 5 seconds total, expressions average 1.25 seconds
//   - Compare against baseline (no expressions)
//   - Identify which column is slowest via binary elimination (comment out columns, re-reload)

// Result:
// - debug_simple_sum: 300ms (acceptable)
// - debug_set_analysis: 400ms (acceptable)
// - debug_aggr_customer: 2100ms (SLOW - focus optimization here)
// - debug_aggr_rank: 1500ms (SLOW - pre-calculate in load script)

DROP TABLE [_ExpressionTest];
```

**Optimization after profiling:**
- Pre-calculate Aggr(Rank(...)) in load script (store rank in field)
- Reduce Aggr(Sum(), Customer.ID) by using a Customer.SalesTotal pre-calculated field
- Replace set analysis with pre-filtered table if the date range is known at load time

---

## Pattern 9: Memory Profile Checklist

Before deploying a Qlik app, validate memory efficiency:

```
[ ] Field data types optimized:
    [ ] No string ID fields with >1M cardinality (should be numeric)
    [ ] Dates stored as integers (not strings like 'YYYY-MM-DD')
    [ ] Dual values used only when both text + numeric sort needed

[ ] Field count minimized:
    [ ] All metadata fields (load_datetime, source_system) dropped
    [ ] No unused columns loaded from source
    [ ] Fact tables narrowed to keys + measures only

[ ] QVD efficiency:
    [ ] Every QVD read exactly once (no redundant disk reads)
    [ ] Optimized loads used for unfiltered, untransformed QVD reads
    [ ] Preceding LOAD used for transformations instead of standard read

[ ] Memory estimates documented:
    [ ] Source row counts recorded
    [ ] Expected memory footprint per layer (extract, transform, model)
    [ ] Data reduction percentages calculated (source → final)

[ ] Expressions profiled:
    [ ] Slow expressions (>200ms) identified and optimized
    [ ] Nested Aggr() pre-calculated in script
    [ ] Count(DISTINCT) replaced with pre-calculated field where possible

[ ] Calculation conditions applied:
    [ ] High-cardinality expressions limited via condition + message variable
    [ ] Expensive aggregations suppressed when context doesn't support them

[ ] Temp tables cleaned up:
    [ ] Every _table has a DROP statement
    [ ] Peak memory during load < 2x final model size
```

---

## References

See SKILL.md for explanation of each optimization technique. Use Qlik Cloud's "Application performance evaluation" for app-specific sheet/object-level profiling.
