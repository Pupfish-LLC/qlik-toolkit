# Qlik Data Modeling Anti-Patterns

Common modeling mistakes, their real failure modes, and the fixes. All code samples are valid Qlik script — no SQL `ON` clauses, no `OVER (PARTITION BY)`, no SQL-style JOINs.

---

## 1. Synthetic Keys from Generic Field Names

### The Wrong Way

```qlik
[Product]:
LOAD product_id, Status, Code, Type FROM product.qvd (qvd);

[Order]:
LOAD order_id, product_id, Status, Code, Type FROM order.qvd (qvd);
```

### Why It's Wrong

Both tables share `product_id`, `Status`, `Code`, and `Type`. Because Qlik associates on **every** matching field name, it creates a synthetic key composed of all four. In the data model viewer this shows up as a `$Syn 1` synthetic-key table with **solid** connector lines to Product and Order — not a dotted line (dotted lines indicate loose coupling / broken circular references, which is a different problem, see #3).

**Failure mode:** selecting a product status silently filters orders by the same status value. Aggregations across both tables include rows that happen to match on incidental fields. The reload succeeds without warning.

### Detection

- Data model viewer shows a `$Syn` table.
- Script log: lines like `Synthetic key for table [Product]`.
- Two tables share more than one field name.

### The Fix

Entity-prefix the non-key fields so only `product_id` is shared:

```qlik
[Product]:
LOAD
    product_id,
    Status AS [Product.Status],
    Code   AS [Product.Code],
    Type   AS [Product.Type]
FROM product.qvd (qvd);

[Order]:
LOAD
    order_id,
    product_id,
    Status AS [Order.Status],
    Code   AS [Order.Code],
    Type   AS [Order.Type]
FROM order.qvd (qvd);
```

---

## 2. AutoNumber in the QVD Layer

### The Wrong Way

```qlik
[_RawOrder]:
LOAD
    AutoNumber(source_order_id & '|' & source_line_num) AS order_key,
    order_amount
FROM [lib://Source/source.qvd] (qvd);

STORE [_RawOrder] INTO [lib://QVDs/Raw_Order.qvd] (qvd);
```

### Why It's Wrong

`AutoNumber` assigns integers in the order values are first seen during **this reload**. If the source order changes, or a new row arrives between two existing rows, the same business key can receive a different AutoNumber value on the next reload. Storing that to a QVD means the persisted surrogate is unstable across runs.

**Failure mode:** an incremental load matching on `order_key` finds no matches, reloads everything as new, and duplicates accumulate.

### The Fix

Use `Hash128` / `Hash256` for persisted surrogates (deterministic across reloads), or defer `AutoNumber` to the final in-memory model load that is not stored:

```qlik
// Option A — deterministic hash, safe to STORE
[_RawOrder]:
LOAD
    Hash128(source_order_id, '|', source_line_num) AS order_key,
    order_amount
FROM [lib://Source/source.qvd] (qvd);

STORE [_RawOrder] INTO [lib://QVDs/Raw_Order.qvd] (qvd);

// Option B — AutoNumber only in the final Model load (not stored to QVD)
[Model_Order]:
LOAD
    AutoNumber(order_key) AS [%OrderKey],
    order_amount
FROM [lib://QVDs/Transform_Order.qvd] (qvd);
```

---

## 3. Circular References — and How They Differ from Synthetic Keys

### The Wrong Way

```qlik
[Sales]:
LOAD [Customer.Key], [Product.Key], amount FROM sales.qvd (qvd);

[Customer]:
LOAD [Customer.Key], [Region.Key], [Customer.Name] FROM customer.qvd (qvd);

[Region]:
LOAD [Region.Key], [Product.Key], region_name FROM region.qvd (qvd);
```

### Why It's Wrong

There are two paths from Sales to Region: directly via `Product.Key` (Sales → Region) and indirectly via `Customer.Key` then `Region.Key` (Sales → Customer → Region). That closed loop is a **circular reference**.

Qlik's default response is to "loosely couple" one of the tables in the loop — you can see this as a **dotted** connector line in the data model viewer. A loosely coupled table does **not propagate selections** through its associations: selections made elsewhere in the model no longer reach the loosely coupled table, and filtering behavior becomes inconsistent depending on which table the user clicked in.

**Synthetic keys ≠ circular references.** A synthetic key (#1) is Qlik's solution to two tables sharing more than one field — represented as a `$Syn` table with solid lines. A circular reference is two or more tables forming a closed loop — represented with a dotted line on the loosely coupled table. Fixes are different.

### Detection

- Script log warning mentioning circular reference / loosely coupled table.
- Data model viewer shows a dotted connector line.
- Selections propagate to part of the model but not the rest.

### The Fix

Break the loop. Usually the right move is to consolidate the redundant key path into a single dimension, or introduce a **link table** that becomes the sole hub for the shared keys:

```qlik
// Link table approach: one table owns all the shared keys
[_Link]:
LOAD DISTINCT [Customer.Key], [Product.Key], [Region.Key] RESIDENT [Sales];

CONCATENATE([_Link])
LOAD DISTINCT [Customer.Key], [Region.Key] RESIDENT [Customer];

// Strip the redundant keys off the dimensions so Sales -> _Link -> Dims
// is the only path.
DROP FIELDS [Product.Key], [Region.Key] FROM [Customer];
DROP FIELDS [Product.Key] FROM [Region];
```

---

## 4. QUALIFY on Pre-Prefixed Fields

### The Wrong Way

```qlik
// Fields already use entity-prefix notation
[Customer]: LOAD customer_id, [Customer.Name] FROM customer.qvd (qvd);
[Order]:    LOAD order_id, customer_id, [Order.Status] FROM order.qvd (qvd);

QUALIFY *;
UNQUALIFY customer_id, order_id;

[AnotherTable]:
LOAD customer_id, [Customer.Name] FROM another.qvd (qvd);
```

### Why It's Wrong

`QUALIFY` prepends the **loaded table's label** to each non-excluded field at load time. If `[AnotherTable]` loads a field that is already called `[Customer.Name]`, QUALIFY turns it into `[AnotherTable.Customer.Name]`. Expressions in the UI still reference `[Customer.Name]`, so they now resolve against the original Customer table only and silently ignore the other source.

**Failure mode:** dashboard cells show partial data (or `-`). No error. The divergence only becomes visible when someone reconciles totals.

### The Fix

Don't combine QUALIFY with a hand-maintained prefix convention. Pick **one** discipline: either use explicit column lists with manual prefixing (preferred when the team is already aliasing fields), or use QUALIFY on un-prefixed raw loads and accept the `TableName.FieldName` convention it produces.

---

## 5. Multiple Shared Fields Between Two Tables

### The Wrong Way

```qlik
[Order]:
LOAD order_id, customer_id, [Order.Amount] FROM order.qvd (qvd);

[OrderDetail]:
LOAD order_id, customer_id, detail_id, [Detail.Quantity] FROM orderdetail.qvd (qvd);
```

### Why It's Wrong

Both tables share `order_id` **and** `customer_id`. Qlik creates a synthetic key on the pair even though the real relationship between the two tables is just `order_id` — `customer_id` is only in OrderDetail for denormalization convenience.

### The Fix

Drop the redundant field from the child table (customer_id is already reachable through Order), or rename it:

```qlik
[OrderDetail]:
LOAD
    order_id,
    detail_id,
    [Detail.Quantity]
FROM orderdetail.qvd (qvd);
```

---

## 6. Missing Bridge Table for Many-to-Many

### The Wrong Way

```qlik
[Product]:
LOAD
    product_id,
    product_name,
    Concat(DISTINCT category, ', ') AS categories_list
FROM [raw_product_category.qvd] (qvd) GROUP BY product_id, product_name;
```

### Why It's Wrong

Flattening many-to-many relationships into a delimited string removes the user's ability to filter by an individual value. Substring matching against the concatenated list is fragile (`'Electronics'` will match `'Electronics Accessories'`).

### The Fix

```qlik
[Product]:
LOAD DISTINCT product_id, product_name FROM [raw_product.qvd] (qvd);

[ProductCategory]:
LOAD DISTINCT
    product_id,
    category AS [Product.Category]
FROM [raw_product_category.qvd] (qvd);
```

One row per product-category pair. Users can filter `[Product.Category]` and the bridge naturally propagates to the product list.

---

## 7. Wide Format for an Expanding Dimension

### The Wrong Way

```qlik
[EntitySourceCoverage]:
LOAD
    entity_id,
    In_Source_A,
    In_Source_B,
    In_Source_C
FROM coverage.qvd (qvd);
```

Expressions hard-code each source:

```qlik
Sum({<In_Source_A = {1}>} amount) + Sum({<In_Source_B = {1}>} amount) ...
```

### Why It's Wrong

Each new source requires touching the ingest, the LOAD, and every expression. New source data is loaded but silently excluded from totals.

### The Fix

Pivot to long format — one row per entity-source combination — and filter on the source column:

```qlik
[EntitySourceCoverage]:
LOAD DISTINCT
    entity_id,
    source_name AS [Source.Name]
FROM coverage_normalized.qvd (qvd);
```

New sources appear automatically in the `[Source.Name]` filter pane.

---

## 8. Ignoring Source Architecture

### The Wrong Way

Treating Data Vault, OLTP, and dimensional-warehouse sources identically — pulling every table as-is without applying the right consumption pattern.

### Why It's Wrong

- **Data Vault** satellites must be joined to their hub, and (for insert-only variants) filtered to the current version before consumption.
- **OLTP** sources need denormalization to avoid forcing end users through a dozen bridge hops for every question.
- **Dimensional warehouses** (Kimball) can usually be loaded nearly as-is.
- **Pre-joined views** require grain validation — a "one row per customer" view often isn't.
- **Flat files** need deduplication, codepage handling, and quote parsing.

### The Fix

Use valid Qlik script joins (no SQL `ON` clause). The `LEFT JOIN` / `INNER JOIN` prefix joins on **all** matching field names in the table being loaded into:

```qlik
// Data Vault: merge hub + current-version satellite into one dimension
[Customer]:
LOAD
    customer_hub_key,
    business_key
FROM [lib://QVDs/dv_customer_hub.qvd] (qvd);

LEFT JOIN ([Customer])
LOAD
    customer_hub_key,
    [Customer.Name],
    [Customer.LoadDate]
FROM [lib://QVDs/dv_customer_sat.qvd] (qvd)
WHERE [Customer.LoadDate] = Peek('MaxLoadDate', 0, 'MaxPerHub');
// (MaxPerHub is a resident max-per-hub table built earlier — see
// source-consumption-patterns.md for the full Data Vault pattern.)
```

```qlik
// OLTP: denormalize customer attributes onto the order fact
[Order]:
LOAD
    order_id,
    customer_id,
    order_date,
    [Order.Amount]
FROM [lib://QVDs/oltp_order.qvd] (qvd);

LEFT JOIN ([Order])
LOAD
    customer_id,
    [Customer.Region],
    [Customer.Segment]
FROM [lib://QVDs/oltp_customer.qvd] (qvd);
```

See **source-consumption-patterns.md** for the full patterns per source type.

---

## 9. Disconnected Tables (Data Islands)

### The Wrong Way

```qlik
[Sales]:   LOAD product_id, amount FROM sales.qvd (qvd);
[Product]: LOAD product_id, name FROM product.qvd (qvd);
[Budget]:  LOAD budget_id, amount FROM budget.qvd (qvd);
```

Budget shares no field with the other tables. Selecting a product does not filter budget.

### The Fix

Give Budget a shared key (`product_id`, or a date key, etc.) so selections propagate. If the budget is legitimately disconnected at the row level (e.g., total-company target), keep it isolated but surface it explicitly as a KPI rather than letting users assume it filters.

---

## 10. Over-Modeling Tiny Lookups

### The Wrong Way

Creating a two-field lookup table (`status_code → status_description`) as a full dimension when the description is the only thing the UI needs.

### The Fix

Use `ApplyMap` to resolve the description at load time — but **only when the lookup really is a single attribute**. If users need to filter on `status_category`, `status_severity`, *and* `status_description`, keep it as a proper dimension table; mapping away multiple attributes forces you to either create multiple maps (losing the link between attributes) or concatenate them into a single string (back to anti-pattern #6).

```qlik
[Map_Status]:
MAPPING LOAD status_code, status_description FROM status_ref.qvd (qvd);

[Order]:
LOAD
    order_id,
    status_code,
    ApplyMap('Map_Status', status_code, 'Unknown') AS [Order.Status]
FROM order.qvd (qvd);
```

---

## 11. Missing "No Entry" Rows in Bridge Tables

### The Wrong Way

A bridge table only contains rows for products that actually have a category. When the user selects any category, products with no category vanish from every chart.

### The Fix — Using the Aliased EXISTS Pattern

```qlik
[ProductCategory]:
LOAD
    product_id,
    category AS [Product.Category]
FROM [lib://QVDs/raw_product_category.qvd] (qvd);

// Add a "No Entry" row for every product that is not already in the bridge.
// The aliased EXISTS pattern: load product_id under a different alias first,
// then EXISTS against that alias so the concatenate load sees only products
// that are NOT already present.
[_CategorizedProducts]:
LOAD DISTINCT product_id AS _categorized_id RESIDENT [ProductCategory];

CONCATENATE ([ProductCategory])
LOAD
    product_id,
    'No Entry' AS [Product.Category]
FROM [lib://QVDs/raw_product.qvd] (qvd)
WHERE NOT EXISTS(_categorized_id, product_id);

DROP TABLE [_CategorizedProducts];
```

Every product now has at least one bridge row. Category-driven charts still include the "no category" bucket when that selection is active.

---

## 12. Incorrect Grain Alignment Between Facts

### The Wrong Way

```qlik
[Fact_Daily]:
LOAD [Date.Key], [Product.Key], daily_amount FROM daily_sales.qvd (qvd);

[Fact_Monthly]:
LOAD [Date.Key], [Product.Key], monthly_amount FROM monthly_sales.qvd (qvd);

[Dim_Date]:
LOAD [Date.Key], date, month FROM dim_date.qvd (qvd);
```

### Why It's Wrong

Both facts share `[Date.Key]` and `[Product.Key]` with each other, creating a synthetic key directly between the two fact tables. Even once that's fixed via a link table, the semantic problem remains: users who build a chart dimensioned on `month` and expression `Sum(daily_amount) + Sum(monthly_amount)` are double-counting, because the same month contains both daily rows and a monthly roll-up.

**Real failure modes:**

1. Synthetic key between the two facts (structural — breaks filtering).
2. Cross-fact summation overstates totals (semantic — wrong numbers).
3. Chart context confusion — users don't know which fact their expression is hitting.

### The Fix

Pick one of:

- **Concatenate** the two facts into a single table with a `[Fact.Type]` discriminator, and require expressions to filter on it (`Sum({<[Fact.Type]={'Daily'}>} amount)`).
- **Link table** intermediating both facts to the shared dimensions, so each fact retains its own grain and associations propagate cleanly through the link.
- **Drop one of the facts** if the monthly roll-up is just `Sum(daily)` — keep the daily grain and let Qlik aggregate.

---

## Summary Table

| Anti-Pattern | Failure Mode | Detection | Fix |
|---|---|---|---|
| 1. Synthetic keys from generic names | Silent unintended filtering | `$Syn` table in viewer, solid lines | Entity-prefix non-key fields |
| 2. AutoNumber in QVD layer | Non-deterministic surrogates break incremental | Reload twice, keys differ | Hash keys; AutoNumber only in final model |
| 3. Circular references | Loosely coupled table, inconsistent selection propagation | Dotted connector, script log warning | Consolidate key paths or use a link table |
| 4. QUALIFY on pre-prefixed fields | Fields double-prefixed, expressions go silent | Weird `Tbl.Entity.Field` names | Don't mix QUALIFY with manual prefixing |
| 5. Multiple shared fields | Synthetic key between a pair of tables | `$Syn` table | Drop the redundant field |
| 6. Missing bridge table | Users can't filter individual many-to-many values | Delimited string columns | Bridge table |
| 7. Wide format expansion | New values silently excluded from totals | Hard-coded `Source_A/B/C` columns | Pivot to long format |
| 8. Ignoring source architecture | Wrong grain, missing merges, broken DV satellites | Model doesn't match source shape | Apply the per-source consumption pattern |
| 9. Data islands | Selections don't propagate | Separate clusters in viewer | Add a shared key (or make the island explicit) |
| 10. Over-modeling tiny lookups | Needless tables, collision risk | 2-field lookup dimensions | `ApplyMap` — but only for single-attribute lookups |
| 11. Missing "No Entry" rows | Rows disappear when bridge is filtered | Row-count mismatch Bridge vs Parent | Aliased `EXISTS` + concatenate "No Entry" rows |
| 12. Grain misalignment | Synthetic key + double-counted totals | Two facts share multiple dim keys directly | Concatenate with type discriminator, or link table |
