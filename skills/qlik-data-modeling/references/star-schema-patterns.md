# Star Schema Patterns in Qlik

Detailed patterns for building normalized and denormalized dimension/fact structures in Qlik Sense.

---

## Bridge Tables for One-to-Many Relationships

When a dimension entity has a one-to-many attribute (a product with multiple categories, a customer with multiple addresses, a person with multiple race values), create a separate bridge table rather than concatenating values or flattening to a single row.

### The Pattern: Bridge Table with Aliased EXISTS and "No Entry" Rows

A bridge connects a parent entity (e.g., `[Product]`) to a child reference table (e.g., `[Category]`) when one parent can map to many children. The bridge carries **only the foreign keys** — the descriptive attributes live on the child dimension. This is the critical rule: if the bridge also carries `[Category.Label]`, it shares two fields with `[Category]` and Qlik builds a synthetic key. See `anti-patterns.md` § 5 (Multiple Shared Fields).

Three tables participate:

1. **`[Product]`** — parent entity, one row per product, keyed by `product_id`.
2. **`[Category]`** — child dimension, one row per category, keyed by `[Category.Code]`, carrying `[Category.Label]`.
3. **`[ProductCategoryBridge]`** — many-to-many link, one row per product/category pair, carrying **only** `product_id` and `[Category.Code]`.

```qlik
// 1. Parent entity (assumed loaded earlier in the script)
[Product]:
LOAD product_id, [Product.Name]
FROM [lib://QVDs/raw_product.qvd] (qvd);

// 2. Category dimension — owns the descriptive attribute [Category.Label].
//    Include a 'NONE' sentinel row so products with no category still display
//    a meaningful label via the dimension join.
[Category]:
LOAD DISTINCT code AS [Category.Code], label AS [Category.Label]
FROM [lib://QVDs/raw_category.qvd] (qvd);

CONCATENATE ([Category])
LOAD * INLINE [
    [Category.Code], [Category.Label]
    NONE, No Entry
];

// 3. Bridge — carries ONLY the keys. No [Category.Label] here; it lives on [Category].
[ProductCategoryBridge]:
LOAD product_id, code AS [Category.Code]
FROM [lib://QVDs/raw_product_category.qvd] (qvd);

// 4. Aliased EXISTS lookup for products that already have a bridge row.
[_HasCategory]:
LOAD DISTINCT product_id AS _has_category RESIDENT [ProductCategoryBridge];

// 5. Add the sentinel ('NONE') bridge row for products with no category,
//    so they remain visible when the user filters on [Category.Label].
CONCATENATE ([ProductCategoryBridge])
LOAD DISTINCT
    product_id,
    'NONE' AS [Category.Code]
RESIDENT [Product]
WHERE NOT EXISTS(_has_category, product_id);

DROP TABLE [_HasCategory];
```

Resulting associations: `[Product] —product_id— [ProductCategoryBridge] —[Category.Code]— [Category]`. Each association shares exactly one field — no synthetic key. (See `qlik-data-modeling` § 1, The One-Key Rule.)

### Why Aliased EXISTS?

The EXISTS function checks the **entire symbol space** (all tables with that field name). Without aliasing the lookup field (`_has_category`), an EXISTS on `product_id` would incorrectly check every table holding `product_id` — including `[Product]` itself — and skip every row, defeating the "No Entry" insertion.

**The aliasing pattern is critical:** Load the distinct keys to a temp table with an alias, use the alias in the EXISTS check, then drop the temp. This ensures EXISTS checks only the specific values you need.

### "No Entry" Rows: When to Use

Include "No Entry" rows when the parent entity must remain visible during selections on the bridge dimension. Example: if a product has no categories assigned, a user selecting a category should still see that product with a "No Entry" entry (or use a flag to hide it).

**Skip "No Entry" rows when:** Absence correctly means the relationship does not exist. Example: a customer with no orders should not appear in an OrderCustomer bridge with a "No Entry" entry.

### When to Bridge vs. Flatten

**Use a bridge when:**
- An entity can have multiple values (product with N categories, customer with N addresses).
- The many-side must drive selections (filtering on categories should affect products).
- All many-side values must be visible in analysis (no arbitrary "pick first" rule).

**Flatten via LEFT JOIN when:**
- The relationship is genuinely 1:1 (most recent address, primary contact).
- The dedup rule is well-defined and documented (e.g., "order by date DESC, pick first").
- Flattening reduces model complexity without losing information.

Example of flattening (in Transform layer, before model load). `LEFT JOIN` is a **load prefix** in Qlik — it joins the incoming LOAD into an existing table on **all matching field names**, with no `ON` clause:

```qlik
[Product]:
LOAD product_id, name FROM [lib://QVDs/raw_product.qvd] (qvd);

// LEFT JOIN prefix: attach primary category onto the Product table.
// Picks the first category per product via a FirstValue aggregation.
LEFT JOIN ([Product])
LOAD
    product_id,
    FirstValue(category_name) AS [Product.PrimaryCategory]
FROM [lib://QVDs/raw_product_category.qvd] (qvd)
GROUP BY product_id;
```

This produces ONE row per product with the primary category, reducing table count.

### When Wide IS Appropriate

- The column set is truly fixed and known (unlikely to grow).
- Front-end performance benefits from pre-computed flags (e.g., binary columns for ranking).
- Source system delivers wide format and de-normalization cost is high.

**Rare in practice.** Default to normalized format.

---

## Link Tables for Multiple Fact Tables

When two or more fact tables at the same grain share the same set of dimension keys, connecting them directly to all dimensions creates a circular reference. A link table breaks the ambiguity.

### The Problem

```
Fact_Sales ----[Product.Key]----> Dim_Product
  |
  +---[Store.Key]----> Dim_Store

Fact_Returns ----[Product.Key]----> Dim_Product
  |
  +---[Store.Key]----> Dim_Store

Qlik sees two paths from Sales to Returns: via Product and via Store.
This circular reference causes unpredictable filtering behavior.
```

### The Link Table Solution

Create a composite key from the shared dimensions:

```qlik
// 1. Extract unique dim-key combinations from each fact
[Link_ProductStore]:
LOAD DISTINCT [Product.Key], [Store.Key] RESIDENT [Fact_Sales];

CONCATENATE ([Link_ProductStore])
LOAD DISTINCT [Product.Key], [Store.Key] RESIDENT [Fact_Returns];

// 2. Strip the dimension keys off the facts and replace with a composite
//    link key so each fact associates to the link table, not the dims.
//    (Easier alternative: leave the keys on the facts if there is only
//    one path — a link table is only needed when the direct associations
//    would form a loop.)

// 3. Facts connect to Link_ProductStore; Link_ProductStore connects to dims.
// Fact_Sales ----[Product.Key, Store.Key]----> Link_ProductStore <----[Product.Key]---- Dim_Product
//                                                          |
//                                              [Store.Key] |
//                                                          v
//                                                   Dim_Store
```

### When to Use Link Tables

- **Circular references:** Two fact tables share multiple dimensions.
- **Multi-grain facts:** Multiple facts at different grains sharing dimensions (use link table + grain type field).
- **Many-to-many disambiguation:** Explicitly structure ambiguous relationships.

### Deferral Rule

Defer link table creation until the model actually requires it. Do not preemptively build link tables for relationships that don't yet exist. Start with direct connections, introduce a link table only when circular references appear.

---

## Mapping Tables via ApplyMap (Lookups)

When a table's only purpose is to provide lookup attributes (mapping an ID to a description), consume it via ApplyMap rather than loading it as a separate table. This reduces table count and avoids synthetic keys.

### The Pattern

```qlik
// Create a mapping table (temporary, resident only)
[_StatusMap]: LOAD status_code, status_description FROM [status_reference.qvd] (qvd);

// Convert to mapping (for fast lookup)
Map_Status: MAPPING LOAD status_code, status_description RESIDENT [_StatusMap];

// Drop the resident table
DROP TABLE [_StatusMap];

// Apply the mapping in your target LOAD
[Order]:
LOAD
    order_id,
    status_code,
    ApplyMap('Map_Status', status_code, 'Unknown') AS [Order.Status]
FROM [order.qvd] (qvd);
```

### Benefits

- **Reduced table count:** One fewer table in the data model viewer.
- **No synthetic keys:** The mapping table never shares fields with other tables.
- **Simple lookup semantics:** Clear that status_code is a foreign key reference.

### When NOT to Use ApplyMap

- The lookup table has multiple fields needed for filtering or display (use a bridge or separate dimension).
- The lookup table participates in complex relationships (use as a proper dimension table).
- Performance: If the mapping is very large (millions of entries), a resident mapping may be slower than a joined dimension.

### Load Once, Create Multiple Maps

Never read the same QVD multiple times. Load to a resident temp table, create maps from it, drop the temp:

```qlik
[_TempRef]: LOAD code, name, category, priority FROM [reference.qvd] (qvd);

Map_Name: MAPPING LOAD code, name RESIDENT [_TempRef];
Map_Category: MAPPING LOAD code, category RESIDENT [_TempRef];
Map_Priority: MAPPING LOAD code, priority RESIDENT [_TempRef];

DROP TABLE [_TempRef];
```

---

## Normalized Over Wide for Expanding Dimensions

When a dimension set will grow over time (new source tables being added, new categories appearing), prefer **normalized (long) format** over **wide (pivoted) format** in the data model.

### The Problem with Wide Format

Wide format hard-codes column names as references throughout the script and expressions:

```
WRONG (wide format):
entity_id | In_Source_A | In_Source_B | In_Source_C
123       | 1           | 0           | 1

Adding Source D requires:
1. SQL script change: SELECT entity_id, source_a, source_b, source_c, source_d FROM table
2. Qlik script change: LOAD entity_id, In_Source_A, In_Source_B, In_Source_C, In_Source_D
3. Expression changes in front-end: IF(In_Source_D, ...)
4. Data dictionary updates

Every new category requires changes in multiple places.
```

### The Solution: Normalized (Long) Format

Store the category as a data value, not a column name. New categories appear automatically:

```
RIGHT (normalized format):
entity_id | source_name
123       | source_a
123       | source_b
123       | source_c

Adding Source D:
1. Source SQL: unchanged (selects entity_id, source_name from table)
2. Qlik script: unchanged
3. Expressions: unchanged
4. Data appears automatically when loaded

The front-end handles the pivot via set analysis, pivot tables, or calculated dimensions.
```

### Implementation: SubField Expansion into Bridge Table

If source data arrives as a delimited list, expand into normalized form via SubField:

```qlik
// Source: entity_id | sources (comma-delimited like "source_a,source_b,source_c")
[_SourceList]:
LOAD entity_id, sources FROM [source.qvd] (qvd);

// Expand into bridge table
[EntitySource]:
LOAD
    entity_id,
    Trim(SubField(sources, ',', IterNo())) AS [Source.Name]
RESIDENT [_SourceList]
WHILE Len(Trim(SubField(sources, ',', IterNo()))) > 0;

DROP TABLE [_SourceList];
```

Result: One row per entity-source combination, normalized and ready for bridge table patterns.

### When to Use Normalized Format

- Dimension attributes will grow over time (new categories, new sources).
- Data should drive structure, not column names.
- Query expressions should be stable across time.

**Default to normalized format.** Wide format requires structural changes when categories expand.

---

## Hiding Technical Keys from Users

Use `SET HidePrefix = '%'` (composite keys) and `SET HideSuffix = '_key'` (source surrogate keys) to keep technical key fields out of filter panes while preserving them for associations. Both can coexist; a field matching either pattern is hidden. Apply the SET statements early (typically in `01_Config.qvs`) before any LOAD that creates hidden fields.

See `qlik-naming-conventions` § Key Field Naming for the full convention (when to use `%` vs. `_key`, the composite key construction pattern, and the anti-patterns to avoid).

---

## Dimension vs. Fact Classification

Classifying a table as dimension or fact is not always obvious. This classification affects key strategy, incremental load pattern, and model structure.

### Dimension Characteristics

- **Slowly changing:** Updates infrequently (weekly, monthly, or quarterly).
- **Lookup semantics:** Its purpose is to provide descriptive attributes for facts.
- **Small-to-medium size:** Usually much smaller than fact tables.
- **One key field:** Links to facts through a single key.
- **No measurable quantities:** Rows do not have measures (quantities, amounts, counts) that aggregate meaningfully.

Examples: Product, Customer, Store, Date, Employee.

### Fact Characteristics

- **Frequently occurring events:** New rows added regularly (daily, hourly, per transaction).
- **Grain:** Every row represents an event at a specific grain (order line, daily sales, hourly click).
- **Measure-oriented:** Contains quantifiable fields (quantity, amount, duration, count).
- **Links to dimensions:** Associates to multiple dimension tables via key fields.
- **Large:** Often the largest table in the model.

Examples: Orders, OrderLine, Sales, Transactions, Page Views.

### Common Ambiguities

**Slowly-changing dimensions (SCD):** A customer table that updates as customer attributes change. Classified as a **dimension** (not a fact), but handled with special incremental logic. See `qlik-load-script` skill for SCD Type 1 and Type 2 patterns.

**Transaction-like dimensions:** An Employee table that grows as employees are hired. Classified as a **dimension** (not a fact), even though rows are added frequently. The key difference: rows don't aggregate into meaningful measures.

**Factless facts:** A fact table with only key fields (no measures), like a registration or event occurrence table. Still a **fact** (because rows are events), but the focus is on which dimensions co-occur, not on aggregating measures.

### Impact on Modeling Decisions

| Decision | Dimension | Fact |
|----------|-----------|------|
| **Key type** | Natural or surrogate (from data warehouse) | Composite or AutoNumber (for large string keys) |
| **Incremental pattern** | SCD Type 1 (update) or Type 2 (history) | Insert-only append, or full replace |
| **Size handling** | Usually small; ApplyMap for very small lookups | QVD layer for large volumes |
| **Grain alignment** | Reference multiple fact tables at different grains | Must have consistent grain |

---

## Dimension Grain and Cardinality

**Grain:** The level of detail represented by one row.
- Product dimension grain: one row per product.
- Date dimension grain: one row per day.
- Store dimension grain: one row per store location.

**Cardinality:** The number of unique values.
- If there are 10,000 products, Product dimension has cardinality 10,000.
- If a date dimension covers 10 years of daily data, it has cardinality ~3,650.

Cardinality matters for performance. Very high cardinality dimensions (millions of values) may not perform well in filter panes; consider ApplyMap or search-based filtering for such cases.

---

## Multi-Valued Dimension Keys

Rarely, a dimension may require multiple key fields to be fully identified. This is a sign the dimension should be decomposed or the model restructured.

### When This Occurs

- A slowly-changing dimension with SCD Type 2 may have both a system-assigned key and an effective-date range.
- A geopolitical dimension may require both country code and region code to be unique across time.

### Pattern: Composite Key Bridge

Instead of having two separate key fields in the dimension, create a composite key:

```qlik
[Dimension]:
LOAD
    dimension_id,
    Hash128(business_key & '|' & effective_date) AS [%DimensionKey],
    [Dimension.Attribute1],
    [Dimension.Attribute2]
FROM [source.qvd] (qvd);

[Fact]:
LOAD
    fact_id,
    fact_measure,
    Hash128(business_key & '|' & effective_date) AS [%DimensionKey]
FROM [fact.qvd] (qvd);
```

The composite key is hashed (deterministic) and used to link both tables. Dimensions and facts associate through the composite key only.

---

## SubField Expansion for Array/List Fields

When source fields contain delimited lists (e.g., comma-separated categories, pipe-delimited tags), expand them into normalized form using SubField + IterNo() to create bridge tables.

### Pattern: SubField with WHILE Loop

```qlik
// Source table with delimited list
[_SourceProduct]:
LOAD product_id, categories  // categories = "cat1,cat2,cat3"
FROM [product.qvd] (qvd);

// Expand into bridge table: one row per product-category combination
[ProductCategory]:
LOAD
    product_id,
    Trim(SubField(categories, ',', IterNo())) AS [Product.Category]
RESIDENT [_SourceProduct]
WHILE Len(Trim(SubField(categories, ',', IterNo()))) > 0;

DROP TABLE [_SourceProduct];
```

Result: Each product-category pair becomes a row, normalized for correct aggregation and filtering.

### Cleaning Before Expansion

Always clean delimiters before expanding:

```qlik
// Remove wrapping brackets, quotes, etc.
[_CleanedProduct]:
LOAD
    product_id,
    PurgeChar(categories, '[]{}' & Chr(34)) AS categories
RESIDENT [_SourceProduct];

// Then expand
[ProductCategory]:
LOAD
    product_id,
    Trim(SubField(categories, ',', IterNo())) AS [Product.Category]
RESIDENT [_CleanedProduct]
WHILE Len(Trim(SubField(categories, ',', IterNo()))) > 0;
```

---

## Summary: When to Use Each Pattern

| Scenario | Pattern | Rationale |
|----------|---------|-----------|
| One entity, multiple values for an attribute | Bridge table with aliased EXISTS | Preserves all relationships |
| Multiple fact tables, same dimensions, same grain | Link table | Prevents circular references |
| Lookup table with one-to-one mapping | ApplyMap | Reduces table count |
| Lookup table with complex filtering | Separate dimension | Full dimension semantics |
| Expanding dimension attributes over time | Normalized (long) format | Auto-expands with new categories |
| Pre-computed attributes for performance | Wide format | Rare; only if column set is truly stable |
| Technical or composite keys | HidePrefix/HideSuffix | Hidden from users, visible to engine |
| Two fact tables, different grains, shared dimensions | Link table + type flag or grain type field | Prevents incorrect aggregations |
| Source field with delimited list | SubField + IterNo expansion | Bridge table pattern for arrays |
