# Qlik Data Modeling Anti-Patterns

Canonical catalog of data-modeling mistakes that produce silent failures or incorrect results in Qlik Sense apps. Each entry covers: how the failure forms, how Qlik signals it, what to do instead. All code samples are valid Qlik script — no SQL `ON` clauses, no `OVER (PARTITION BY)`, no SQL-style JOINs.

This file is the canonical home for synthetic key, circular reference, QUALIFY discipline, and related cross-cutting data-modeling failure modes. Companion files in the same skill cover specific structural patterns (`star-schema-patterns.md`), deployment shapes (`multi-app-architecture.md`), and source-side ingestion strategy (`source-consumption-patterns.md`).

---

## 1. Synthetic Keys from Generic Field Names

### What a synthetic key is

When two tables share **more than one field name**, Qlik cannot pick a single join key, so it creates a hidden composite table named `$Syn 1` (then `$Syn 2`, etc.) that holds every distinct combination of the shared values. Each original table connects to the `$Syn` table by all of the shared fields collectively. In the Data Model Viewer this appears as a separate `$Syn N` node with **solid** connector lines to the contributing tables. Solid lines distinguish synthetic keys from circular references (#3), which use **dotted** lines.

Synthetic keys are not always wrong — Qlik documents them as "valid composite keys" — but they are almost never what the developer intended, and they cause:

- **Silent unintended filtering.** Selecting a value in one shared field filters the other table on the same value, even when that's semantically meaningless.
- **Wrong aggregations.** Rows that happen to match on incidental fields (e.g., both rows have `Status = 'Active'`) get included in cross-table sums.
- **Performance cost.** The `$Syn` table consumes memory and slows engine resolution as the cross-product of shared values grows.
- **No reload error.** The script log emits a `Synthetic key for table [TableName]` line, but the reload succeeds.

### Common triggers

- **Unprefixed generic attribute names** — `Status`, `Code`, `Type`, `Name`, `Description`, `Category` appearing in multiple tables without entity prefixing.
- **Technical / metadata fields** in many raw tables — `load_date`, `source_system`, `created_by`, `record_hash`. None of these carry analytical meaning but all of them associate.
- **Wildcard loads from shared subroutines** — `LOAD *` against a source where some columns happen to share names with another table being loaded in the same script.
- **Denormalized FKs in child tables** — a child table that carries both its own FK to the parent and a duplicate of the parent's FK (e.g., OrderDetail carrying both `order_id` and `customer_id`, when only `order_id` is needed for the relationship — see #5).
- **Wide-format Excel imports** — month columns (`Jan`, `Feb`, `Mar`) that happen to match column names in another sheet's import.

### Detection

- Data Model Viewer shows a `$Syn N` table with solid connector lines.
- Script log: `Synthetic key for table [TableName]` lines.
- Two or more tables share more than one field name (grep the script for repeated `AS [Some.Field]` aliases or repeated unprefixed field references).

### The Wrong Way

```qlik
[Product]:
LOAD product_id, Status, Code, Type FROM product.qvd (qvd);

[Order]:
LOAD order_id, product_id, Status, Code, Type FROM order.qvd (qvd);
```

Both tables share `product_id`, `Status`, `Code`, and `Type`. Qlik creates a `$Syn 1` table; selecting a product `Status` silently filters orders by the same value.

### Prevention — Three Mechanisms

These are the three orthogonal disciplines for preventing synthetic keys. Apply all three at design time, not as fixes after a synthetic key has appeared.

**(a) Distinct entity prefixes on non-key fields.** Generic attribute names like `Name`, `Status`, `Code`, `Type`, `Category` must be entity-prefixed at load time so they cannot collide across tables (`[Product.Status]`, `[Order.Status]`, `[Customer.Region]`). See `qlik-naming-conventions` for the full convention.

**(b) Exactly one shared field per relationship.** For Customer ↔ Order, the only shared field should be the FK (`Customer.CustomerID`). If a denormalized source ships `Customer.Name` into the Order table, Qlik sees two join paths and synthesizes a key. Resolution: rename the duplicate non-key field on the fact side (`Order.CustomerName`).

**(c) Drop or hide metadata fields** (`load_date`, `source_system`, `created_by`, `record_hash`) that appear in many tables but carry no analytical meaning. Either omit them from the LOAD field list or apply a hiding convention (`HidePrefix` / `HideSuffix`) so they cannot participate in associations.

### The Fix (when one has already formed)

Entity-prefix the non-key fields so only the intended FK is shared:

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

For metadata fields that crept in unintentionally, drop them before storing the QVD:

```qlik
DROP FIELDS load_date, source_system, created_by FROM [SomeStagingTable];
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

### What a circular reference is

When three or more tables form a closed loop of single-field associations (A↔B, B↔C, C↔A), Qlik cannot resolve which path a selection should take. The engine's default response is to **loosely couple** one table in the loop — meaning that table's associations no longer propagate selections in either direction.

In the Data Model Viewer this appears as a **dotted** connector line on the loosely coupled table (contrast with the solid lines of a synthetic key). The script log emits a circular reference warning that names the table chosen for loose coupling.

**Failure modes:**
- Selections made elsewhere in the model don't reach the loosely coupled table.
- Filter behavior becomes inconsistent — clicking the same value in two different tables produces different filtered counts.
- Charts that aggregate across the broken path silently omit rows from the loosely coupled side.

### Synthetic keys vs circular references — different problems, different fixes

| | Synthetic Key | Circular Reference |
|---|---|---|
| **Cause** | Two tables share >1 field name | Closed loop of single-field associations A↔B↔C↔A |
| **Viewer signature** | `$Syn` table with **solid** connector lines | **Dotted** connector line on a *loosely coupled* table |
| **Failure mode** | Silent incorrect filtering; extra associations | Loosely coupled table does **not** propagate selections |
| **Fix** | Entity-prefix non-key fields, drop redundant shared fields, or use `ApplyMap` for lookups | Consolidate redundant key paths into one dimension, or introduce a link table; do **not** leave Qlik to pick a loose-coupling victim |

### The Wrong Way

```qlik
[Sales]:
LOAD [Customer.Key], [Product.Key], amount FROM sales.qvd (qvd);

[Customer]:
LOAD [Customer.Key], [Region.Key], [Customer.Name] FROM customer.qvd (qvd);

[Region]:
LOAD [Region.Key], [Product.Key], region_name FROM region.qvd (qvd);
```

There are two paths from Sales to Region: directly via `Product.Key` (Sales → Region) and indirectly via `Customer.Key` then `Region.Key` (Sales → Customer → Region). That closed loop is a circular reference.

### Detection

- Script log warning mentioning circular reference / loosely coupled table.
- Data Model Viewer shows a dotted connector line.
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

## 4. QUALIFY Discipline

### What QUALIFY does

`QUALIFY [field-list]` is a stateful prefix that prepends the loaded table's label to each non-excluded field at load time. `QUALIFY *;` qualifies all fields; `UNQUALIFY [field-list]` carves out exceptions (typically the join keys you need to associate on). The state persists until the next `QUALIFY` / `UNQUALIFY` toggle — including across script tabs.

QUALIFY is one valid tool for preventing synthetic keys on raw or wildcard loads, but it has two well-known failure modes.

### Failure mode A — combined with manual prefixing (double-prefix bug)

If fields are already entity-prefixed by the naming convention, applying `QUALIFY *;` produces double-prefixed names like `[TableName.Customer.Name]`. Expressions in the UI still reference `[Customer.Name]`, so they resolve against the original Customer table only and silently ignore the QUALIFY-loaded source.

```qlik
// Fields already use entity-prefix notation
[Customer]: LOAD customer_id, [Customer.Name] FROM customer.qvd (qvd);
[Order]:    LOAD order_id, customer_id, [Order.Status] FROM order.qvd (qvd);

QUALIFY *;
UNQUALIFY customer_id, order_id;

[AnotherTable]:
LOAD customer_id, [Customer.Name] FROM another.qvd (qvd);
// Result: [Customer.Name] in AnotherTable becomes [AnotherTable.Customer.Name].
// Dashboard cells show partial data from the original Customer table only.
```

**Failure mode:** dashboard cells show partial data (or `-`). No error. The divergence only becomes visible when someone reconciles totals.

**Fix:** don't combine QUALIFY with a hand-maintained prefix convention. Pick **one** discipline:
- Manual prefixing with explicit `AS` aliases (preferred when the team is already aliasing fields). Skip QUALIFY entirely.
- QUALIFY on un-prefixed raw loads. Accept the `TableName.FieldName` convention everywhere and reference fields by that name in expressions.

### Failure mode B — forgetting to UNQUALIFY a key

`QUALIFY *;` qualifies the join keys too. Forgetting to `UNQUALIFY` them yields a silent data model with no associations — every table becomes a data island. Always pair `QUALIFY *;` with an explicit `UNQUALIFY [key-list];` listing every key that should associate.

### Failure mode C — leaving QUALIFY active across tabs

The QUALIFY state persists across tabs and script files until reset. A QUALIFY block in an Extract tab silently affects every subsequent LOAD in Transform and Model tabs unless explicitly reset with `UNQUALIFY *;`. Always reset at the end of the block where you turned it on.

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
| 4. QUALIFY discipline (double-prefix, missing UNQUALIFY, persistent state) | Fields double-prefixed; data islands; cross-tab contamination | Weird `Tbl.Entity.Field` names; no associations; later loads silently qualified | Pick one prefixing discipline; always UNQUALIFY keys; reset state at block end |
| 5. Multiple shared fields | Synthetic key between a pair of tables | `$Syn` table | Drop the redundant field |
| 6. Missing bridge table | Users can't filter individual many-to-many values | Delimited string columns | Bridge table |
| 7. Wide format expansion | New values silently excluded from totals | Hard-coded `Source_A/B/C` columns | Pivot to long format |
| 8. Ignoring source architecture | Wrong grain, missing merges, broken DV satellites | Model doesn't match source shape | Apply the per-source consumption pattern |
| 9. Data islands | Selections don't propagate | Separate clusters in viewer | Add a shared key (or make the island explicit) |
| 10. Over-modeling tiny lookups | Needless tables, collision risk | 2-field lookup dimensions | `ApplyMap` — but only for single-attribute lookups |
| 11. Missing "No Entry" rows | Rows disappear when bridge is filtered | Row-count mismatch Bridge vs Parent | Aliased `EXISTS` + concatenate "No Entry" rows |
| 12. Grain misalignment | Synthetic key + double-counted totals | Two facts share multiple dim keys directly | Concatenate with type discriminator, or link table |
