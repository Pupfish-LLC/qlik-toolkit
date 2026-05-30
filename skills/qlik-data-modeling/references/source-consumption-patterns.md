# Source Architecture Consumption Patterns

How to consume data from different upstream architectures: dimensional warehouses, normalized OLTP, Data Vault 2.0, pre-joined views, and flat files. Each architecture has a different "shape" and a corresponding Qlik consumption strategy. Using the wrong strategy for the source produces silent data loss, wrong grain, or brittle models.

> **Reminder: Qlik script is not SQL.** `JOIN` / `LEFT JOIN` in Qlik is a *prefix* — no `ON` clause, and joins are performed on *all fields with matching names*. There is no `OVER (PARTITION BY ...)`, no `FROM table AS alias`, no `TableName.field` qualification in LOAD field lists, and no SQL `TIMESTAMP 'literal'`. Every code block below uses native Qlik script.

---

## Dimensional Warehouse (Kimball)

Pre-built star schema with surrogate keys and managed dimensions.

### Identifying characteristics

- Integer surrogate keys alongside business keys.
- Dimensions already flattened (denormalized).
- SCD Type 1 or Type 2 already handled upstream.

### Key resolution

Use the warehouse's surrogate keys directly unless there is a reason to rebuild them. They are already stable and unique, and the warehouse maintains referential integrity.

```qlik
[Customer]:
LOAD
    customer_key                  AS [%Customer.Key],
    business_key                  AS [Customer.BusinessKey],
    customer_name                 AS [Customer.Name],
    region                        AS [Customer.Region]
FROM [lib://QVDs/warehouse_customer.qvd] (qvd);

[Fact_Sales]:
LOAD
    sales_key                     AS [%Sales.Key],
    customer_key                  AS [%Customer.Key],
    product_key                   AS [%Product.Key],
    sales_amount                  AS [Sales.Amount]
FROM [lib://QVDs/warehouse_sales.qvd] (qvd);
```

### SCD Type 1 incremental merge

Warehouse overwrites the dimension in place. Merge new rows over old, keyed by the business key.

```qlik
[_DimNew]:
LOAD customer_key AS [%Customer.Key], business_key AS [Customer.BusinessKey],
     customer_name AS [Customer.Name], region AS [Customer.Region]
FROM [lib://QVDs/warehouse_customer.qvd] (qvd);

// Keep old records whose business key is NOT in the new load
[Customer]:
LOAD * FROM [lib://QVDs/Transform_Customer.qvd] (qvd)
WHERE NOT EXISTS([Customer.BusinessKey], [Customer.BusinessKey]);

// Append the new/updated rows
CONCATENATE([Customer])
LOAD * RESIDENT [_DimNew];

DROP TABLE [_DimNew];
STORE [Customer] INTO [lib://QVDs/Transform_Customer.qvd] (qvd);
```

### SCD Type 2: as-of-date set analysis

SCD Type 2 keeps every historical version with `effective_from` / `effective_to` columns. To show "the customer as they were on vAsOfDate", the correct operators are `effective_from <= vAsOfDate AND effective_to >= vAsOfDate`:

```qlik
Sum({<
    [Customer.EffectiveFrom] = {"<=$(=vAsOfDate)"},
    [Customer.EffectiveTo]   = {">=$(=vAsOfDate)"}
>} [Sales.Amount])
```

> **Common bug:** Inverting these operators returns zero rows. The effective row is the one whose validity window *contains* the as-of-date.

### SCD Type 2: load-time effective-date join

The set-analysis pattern above works **at query time** against an SCD2 dimension that is associated to a fact by business key. When you instead need to **resolve each fact row to its in-force dimension version at load time** — flattening the SCD2 history onto the fact — use the `IntervalMatch` prefix with the N-key form on `(transaction_date, business_key)`. Full pattern (one-key + N-key syntax, the standard `LEFT JOIN` + `DROP TABLE` resolution for the structural `$Syn`, NULL upper-bound handling for still-current rows, performance notes, and a worked SCD2 example) lives in `qlik-load-script` → `references/interval-match.md`.

### Pitfalls

- **Treating Type 2 as Type 1.** Dropping `effective_to` or taking only "current" rows throws away history the warehouse paid to maintain.
- **Surrogate-key drift.** If the warehouse ever rebuilds its surrogate strategy, every downstream Qlik model breaks. Keep the business key alongside the surrogate so re-mapping is possible.

---

## Normalized OLTP (3NF)

Operational systems (ERP, CRM, in-house OLTP) store data in many small, highly normalized tables. The source is optimized for transactions, not analytics.

### Identifying characteristics

- Many tables with explicit foreign keys.
- No pre-computed aggregates.
- Operational flag/status/type columns everywhere — these are frequent sources of accidental synthetic keys if field names collide between tables. Alias them with entity prefixes on load.
- Mutable master data (Customer, Product) and append-only transaction tables (Orders, Invoices).

### Key resolution

Use the source primary and foreign keys directly. OLTP keys are stable natural keys; surrogate rebuilding is rarely needed.

### Denormalization: SQL extraction vs. Qlik transform

Star schemas need denormalization. Two places to do it:

**Option A — Join in the SQL extraction.** Push the join down into the `SQL SELECT` so the Raw QVD is already flat:

```qlik
[_RawOrder]:
SQL SELECT
    o.order_id,
    o.customer_id,
    c.name      AS customer_name,
    c.region    AS customer_region,
    o.order_date,
    o.order_amount
FROM oltp.orders o
LEFT JOIN oltp.customers c ON o.customer_id = c.customer_id;

STORE [_RawOrder] INTO [lib://QVDs/Raw_Order.qvd] (qvd);
```

`SQL SELECT` is the one place in a Qlik script where native SQL syntax (including `LEFT JOIN ... ON` and table aliases) is valid — it runs on the source database, not the Qlik engine.

**Option B — Keep Raw normalized, join in Qlik Transform.** The Qlik `LEFT JOIN` prefix joins on *all matching field names* between the target and the loaded table. Rename keys to match, and the join aligns automatically:

```qlik
[Order]:
LOAD
    order_id    AS [%Order.Key],
    customer_id AS [%Customer.Key],
    order_date  AS [Order.Date],
    order_amount AS [Order.Amount]
FROM [lib://QVDs/Raw_Order.qvd] (qvd);

LEFT JOIN ([Order])
LOAD
    customer_id AS [%Customer.Key],
    name        AS [Customer.Name],
    region      AS [Customer.Region]
FROM [lib://QVDs/Raw_Customer.qvd] (qvd);

STORE [Order] INTO [lib://QVDs/Transform_Order.qvd] (qvd);
```

Choose Option A when the source database is well-tuned and the joins are simple. Choose Option B when the joins are complex, need to be reused across several transforms, or need to be debuggable layer-by-layer.

### Transaction table incremental (append-only)

OLTP transaction tables usually only get new rows. Filter on a monotonic timestamp or ID column. Note that `DATE '…'` is SQL syntax; in Qlik use native date literals or `Date#()` parsing:

```qlik
LET vLastLoadDate = Date(Today() - 1, 'YYYY-MM-DD');

[NewOrders]:
SQL SELECT order_id, customer_id, order_amount, order_date
FROM oltp.orders
WHERE order_date > '$(vLastLoadDate)';
```

### Mutable master data (SCD Type 1)

Master tables like Customer and Product update in place. Use the same Type 1 merge pattern as the dimensional-warehouse example above.

### Pitfalls

- **Over-normalizing in Qlik.** If the Qlik model still has 15 3NF tables you haven't moved to a star schema, query performance and user experience both suffer. Denormalize.
- **Duplicate joins.** Joining `Customer` onto `Order` in one place and `Address` onto `Order` in another creates two entry points where field names can collide. Do all the joins in one layer.

---

## Data Vault 2.0

Data Vault 2.0 (Linstedt) is a hybrid architecture designed for raw-history capture, not for querying. Qlik is a consumer — flatten DV into dimensions and facts.

### Identifying characteristics

- **Hubs:** one row per business entity, with a business key and `LoadDate`.
- **Links:** associative tables between hubs.
- **Satellites:** descriptive attributes for a hub, with `LoadDate` (and sometimes `LoadEndDate`). Multiple satellites per hub are normal (one per rate of change or source system).
- Composite business keys are common (`source_system | entity_id`).

### Canonical satellite loading: insert-only + LoadDate

In canonical DV2 (Linstedt & Olschimke, *Building a Scalable Data Warehouse with Data Vault 2.0*), satellites are **insert-only**. When an attribute changes, a new satellite row is inserted with a new `LoadDate`; the previous row is left untouched. End-dating is either computed on read via window functions or stored in a separate Point-in-Time (PIT) table.

For this canonical shape, the incremental filter is a single condition on `LoadDate`:

```qlik
LET vLastLoadTime = Timestamp(Peek('LastRun', 0, '_LoadMetadata'), 'YYYY-MM-DD hh:mm:ss');

[_NewSatRows]:
LOAD
    hub_key           AS [%Customer.HubKey],
    customer_name     AS [Customer.Name],
    region            AS [Customer.Region],
    load_date         AS [Customer.LoadDate]
FROM [lib://QVDs/dv_sat_customer.qvd] (qvd)
WHERE load_date > Timestamp#('$(vLastLoadTime)', 'YYYY-MM-DD hh:mm:ss');
```

### End-dated satellite variant

Some DV2 implementations store an explicit `load_end_date` on satellites and *update* it when a new version arrives (breaking the pure insert-only rule). For this variant — and only this variant — the incremental filter must capture both newly-inserted rows *and* rows whose `load_end_date` was just updated:

```qlik
WHERE load_date > Timestamp#('$(vLastLoadTime)', 'YYYY-MM-DD hh:mm:ss')
   OR load_end_date > Timestamp#('$(vLastLoadTime)', 'YYYY-MM-DD hh:mm:ss')
```

Missing the `load_end_date` clause against end-dated satellites is a silent-failure bug: the load succeeds, but closures are never captured. Before applying this pattern, confirm with the source team which variant they use.

> The *effective* dates (`effective_from`, `effective_to`) used in SCD Type 2 reporting are separate from the *load* dates used for incremental capture. Load dates are technical timestamps (when the row landed); effective dates are business validity dates. Do not conflate them.

### Hub + Satellite flatten to a Qlik dimension

Qlik's `LEFT JOIN` joins on matching field names. Align the key field name, then join:

```qlik
[Customer]:
LOAD
    hub_key       AS [%Customer.HubKey],
    business_key  AS [Customer.BusinessKey]
FROM [lib://QVDs/dv_hub_customer.qvd] (qvd);

LEFT JOIN ([Customer])
LOAD
    hub_key       AS [%Customer.HubKey],
    customer_name AS [Customer.Name],
    region        AS [Customer.Region],
    load_date     AS [Customer.LoadDate]
FROM [lib://QVDs/dv_sat_customer.qvd] (qvd);
```

If multiple satellites share a hub, each is a separate `LEFT JOIN` step. Pick the "current" row per hub before joining using a preceding LOAD with `FirstSortedValue` or an aggregated `LOAD … RESIDENT … GROUP BY hub_key`.

For **point-in-time** satellite lookup (resolve each fact row to the satellite version in force on its transaction date, rather than always taking the current row), use the `IntervalMatch` prefix on `(transaction_date, hub_key)` against the satellite's `load_date` / `load_end_date` (end-dated variant) or a derived effective window (canonical insert-only variant). See `qlik-load-script` → `references/interval-match.md` for syntax, the standard `LEFT JOIN` + `DROP TABLE` resolution of the structural synthetic key, and the SCD2-style worked example.

### Composite business key hashing

When the business key is multi-field, hash the concatenation for a fixed-width, symbol-table-friendly Qlik key:

```qlik
Hash128(source_system & '|' & entity_id) AS [%Entity.Key]
```

`Hash128` is deterministic for a given input string across reloads. Keep the raw business key alongside the hash for debugging.

> Raw string concatenation is *also* deterministic across reloads — the reason to hash is fixed width, collision-resistant joins, and reduced symbol-table cost, not non-determinism. The non-determinism risk applies to `AutoNumber`, not to concatenation or hashing.

### Pitfalls

- **Blindly applying the dual-timestamp rule** to insert-only satellites. It's noise for canonical DV2.
- **Applying single-timestamp filtering** to end-dated satellites. Silent data loss.
- **Dropping history.** Treating DV as Type 1 and keeping only the latest row per hub throws away the whole reason the warehouse uses DV.

---

## Pre-Joined Views and Materialized Exports

Single denormalized tables — database views, materialized exports, API payloads — that combine multiple logical entities.

### Grain is the first question

A `Sales_View` containing customer name, product name, and order amount could be at order grain, order-line grain, or customer-month grain. Sum the wrong column on the wrong grain and you multiply revenue by the number of order lines.

Validate grain at script time by loading an aggregate to a scratch table and peeking the result into a variable:

```qlik
[_GrainCheck]:
LOAD
    Count(DISTINCT order_id)  AS DistinctOrders,
    Count(order_id)           AS TotalRows
RESIDENT [_SalesView];

LET vDistinctOrders = Peek('DistinctOrders', 0, '_GrainCheck');
LET vTotalRows      = Peek('TotalRows', 0, '_GrainCheck');
DROP TABLE [_GrainCheck];

IF $(vDistinctOrders) = $(vTotalRows) THEN
    TRACE Grain is one row per order;
ELSE
    TRACE Grain is finer than order -- likely order line. Aggregate or treat as fact at line grain.;
END IF
```

> `Count(DISTINCT ...)` is an aggregation function; it is only valid inside a LOAD (or a chart expression). `LET x = Count(DISTINCT field);` is NOT valid — use the preceding-LOAD / Peek pattern above.

### Deduplication

Once the grain is known, either `LOAD DISTINCT` the rows that should be unique at the desired grain, or use a preceding-LOAD with `GROUP BY` to collapse to the target grain — never "dedup by guessing." Dedup without grain understanding produces wrong numbers.

### Schema drift

View definitions change silently. At minimum, assert the expected field count and fail the reload if it drifts:

```qlik
[_ViewProbe]:
FIRST 1 LOAD * FROM [lib://QVDs/sales_view.qvd] (qvd);

LET vFields = NoOfFields('_ViewProbe');
DROP TABLE [_ViewProbe];

IF $(vFields) <> 7 THEN
    TRACE [ERROR] Sales view schema drift: expected 7 fields, got $(vFields);
    EXIT SCRIPT;    // hard-fail; do not store stale data
END IF
```

`EXIT SCRIPT` actually halts the reload. `SET ErrorMode = 1` is the engine's default error-handling level and does nothing special on its own.

### Pitfalls

- **Assuming grain.** Every pre-joined view deserves a grain check.
- **Hard-coded field lists without a drift check.** A dropped column is a silent NULL; a renamed column is a silent failure.

---

## Flat Files and CSV Dumps

CSV, TSV, Excel exports, JSON flattened to CSV. Simple to ingest, but schema-less — every assumption needs to be asserted.

### Correct format spec keywords

Qlik's format-spec uses `delimiter is` (not `separator is`). Common parameters:

```qlik
// Comma-delimited, UTF-8, first row is the header, standard quote handling:
LOAD * FROM [lib://Data/orders.csv]
(txt, codepage is 65001, embedded labels, delimiter is ',', msq);

// Pipe-delimited, Latin-1 (Windows-1252), with embedded quoted fields:
LOAD * FROM [lib://Data/orders.txt]
(txt, codepage is 1252, embedded labels, delimiter is '|', msq);

// Tab-delimited:
LOAD * FROM [lib://Data/orders.tsv]
(txt, codepage is 65001, embedded labels, delimiter is '\t', msq);
```

`msq` is "modern-style quoting" — handles embedded delimiters inside double-quoted fields and the `""` escape for literal quotes. Use it on any CSV you don't fully control.

### Header / field-count validation

```qlik
[_OrderProbe]:
FIRST 1 LOAD * FROM [lib://Data/orders.csv]
(txt, codepage is 65001, embedded labels);

LET vFieldCount = NoOfFields('_OrderProbe');
DROP TABLE [_OrderProbe];

IF $(vFieldCount) <> 6 THEN
    TRACE [ERROR] Expected 6 fields in orders.csv, found $(vFieldCount);
    EXIT SCRIPT;
END IF
```

### Incremental by filename glob

Use `FOR EACH … IN FILELIST(...)` — not SQL sub-selects — to loop over matching files:

```qlik
LET vLastLoadTime = Timestamp(Peek('LastRun', 0, '_LoadMetadata'), 'YYYY-MM-DD hh:mm:ss');

FOR EACH vFile IN FILELIST('lib://Data/orders_*.csv')

    // Only load files written since the last successful run
    IF FileTime('$(vFile)') > Timestamp#('$(vLastLoadTime)', 'YYYY-MM-DD hh:mm:ss') THEN

        [_NewRows]:
        LOAD * FROM [$(vFile)]
        (txt, codepage is 65001, embedded labels, delimiter is ',', msq);

        // Overlap guard: if the same order_id already exists, skip it.
        // EXISTS with one argument checks the symbol table of order_id;
        // this is optimized and does NOT force unpack of resident tables.
        IF NoOfRows('Order') > 0 THEN
            CONCATENATE([Order])
            LOAD * RESIDENT [_NewRows]
            WHERE NOT EXISTS(order_id);
        ELSE
            [Order]:
            LOAD * RESIDENT [_NewRows];
        END IF

        DROP TABLE [_NewRows];

    END IF

NEXT vFile
```

### Pitfalls

- **`separator is` instead of `delimiter is`** — not a recognized keyword.
- **Missing `msq`** — any file with embedded commas inside quoted fields will split incorrectly.
- **Encoding mismatch** — loading UTF-8 bytes as `codepage is 1252` silently corrupts accented characters. Verify the source encoding before choosing the codepage.
- **Overlap accumulation** — rolling exports frequently repeat the last N days. Always have a dedup rule (either a primary key + `NOT EXISTS`, or `LOAD DISTINCT` on a composite).

---

## SaaS API Exports (Salesforce, HubSpot, NetSuite, etc.)

Records pulled from a SaaS application via REST/Bulk API or a Qlik connector. The connector hides the API, but the *semantics* of the underlying object model leak through and shape the consumption pattern.

### Identifying characteristics

- **Two timestamp columns** per object: `CreatedDate` and a last-modified timestamp. The two are not interchangeable for incremental capture.
- **Soft deletes.** Deleted rows leave the live object and reappear in a separate "deleted records" endpoint (Salesforce `getDeleted`, the Recycle Bin) until they are purged.
- **History objects** (Salesforce `Account_History`, `Opportunity_History`, etc.) — one row per audited field change, not one row per entity version. Useful for change analysis, dangerous as a substitute for SCD2.
- **Multi-currency** — when enabled, monetary fields are stored in the record's `CurrencyIsoCode` and need to be converted via `CurrencyType` / `DatedConversionRate` before aggregation.
- **Field-level changes** (formula fields, owner changes, automation updates) often update the modified timestamp without any user editing the record.

### Incremental: SystemModstamp over LastModifiedDate

For Salesforce, `SystemModstamp` captures changes from both users *and* automated processes (triggers, workflows, flows, formula recalculation), while `LastModifiedDate` captures only user edits. `SystemModstamp` is also indexed; `LastModifiedDate` typically is not, so SOQL filters on it run unindexed. Use `SystemModstamp` for incremental extracts unless there is a specific reason to track only user-driven changes.

```qlik
LET vLastLoadTime = Timestamp(Peek('LastRun', 0, '_LoadMetadata'), 'YYYY-MM-DDThh:mm:ss.fffZ');

[_NewAccounts]:
SQL SELECT Id, Name, BillingCountry, CurrencyIsoCode, SystemModstamp
FROM Account
WHERE SystemModstamp > $(vLastLoadTime);
```

`LastModifiedDate` can also be back-dated by data-loader imports, which silently drops rows from a filtered incremental window. `SystemModstamp` is set by the platform and cannot be back-dated.

### Soft-deleted records

A record removed by the user moves to the Recycle Bin and disappears from queries against the live object. To keep the Qlik model consistent, query the deleted-records endpoint (Salesforce `getDeleted` for a date range, or `queryAll` to include `IsDeleted = true`) and drive deletions from that list. Without this step, deleted entities remain in QVDs and the model indefinitely.

### History objects

`<Object>_History` rows carry `FieldName`, `OldValue`, `NewValue`, and `CreatedDate`. They are useful for "who changed what when" analysis but are **not** an SCD2 dimension — each row is a single-field delta, not a full snapshot. Treat them as a fact at field-change grain; do not join them to a dimension expecting one row per version.

### Multi-currency

If the org has multi-currency enabled, every monetary field is in the row's `CurrencyIsoCode`. Convert to the corporate currency (or whatever currency the Qlik model reports in) by joining `DatedConversionRate` for the appropriate `CurrencyType` and effective date range. Aggregating mixed-currency amounts without conversion silently sums non-comparable values.

### Pitfalls

- **Using `LastModifiedDate` for incremental.** Misses formula recalculations, workflow updates, owner reassignments, and any change made by an integration user via the API without `LastModifiedDate` write-through. Also runs unindexed on large objects.
- **Ignoring soft deletes.** Deleted records remain in the Qlik model forever.
- **Treating History as SCD2.** Field-change rows do not aggregate to entity versions.
- **Aggregating multi-currency amounts without conversion.** A `SUM(Amount)` across a multi-currency `Opportunity` table is meaningless.

---

## Source Architecture Decision Summary

| Architecture | Key approach | Incremental strategy | Denormalization | What goes wrong |
|---|---|---|---|---|
| Dimensional warehouse | Use surrogate keys as-is; keep business key for debugging | Per warehouse SCD type; merge by business key | Already done | Inverting SCD2 as-of-date operators; treating Type 2 as Type 1 |
| Normalized OLTP | Use PK/FK directly; denormalize in SQL extract or Qlik transform | Append by monotonic column + SCD1 merge on master | Required (SQL extract or Qlik `LEFT JOIN` prefix) | Duplicate joins; field-name collisions on operational flags |
| Data Vault 2.0 | Flatten hubs + satellites; hash composite business keys | LoadDate filter (insert-only) **or** LoadDate + LoadEndDate (end-dated variant) | Flatten satellites per hub | Applying dual-timestamp to insert-only SATs; applying single-timestamp to end-dated SATs |
| Pre-joined view | Validate grain before trusting; dedup deliberately | File timestamp / monotonic column | Already done | Grain drift; dropped columns; accidental fan-out |
| Flat files | Validate field count and encoding; use `msq` for quoted fields | `FILELIST()` + `FileTime()` + dedup on key | Required if source is normalized | Wrong codepage; missing `msq`; overlap not deduped |
| SaaS API exports | Use the platform Id (SF 15/18-char Id, HubSpot recordId) directly; hash if combining systems | `SystemModstamp` (Salesforce) over `LastModifiedDate` + deleted-records endpoint | Usually required (objects are normalized) | Using `LastModifiedDate` misses system updates; ignoring soft deletes; treating History as SCD2; multi-currency without conversion |

**Key takeaway:** the first thing to establish about any new source is which row of this table it sits on. The consumption pattern follows from that.
