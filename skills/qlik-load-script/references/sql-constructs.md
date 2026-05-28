# SQL Constructs Not Valid in Qlik LOAD, and Related Failure Modes

Qlik script resembles SQL but is a fundamentally different language. The single most predictable failure mode for AI-generated scripts is SQL syntax inside `LOAD` or `RESIDENT` statements. This reference covers:

1. SQL syntax that does NOT exist in Qlik `LOAD`/`RESIDENT` (and the Qlik alternative for each)
2. The `SQL SELECT` pass-through exception
3. The five most common adjacent failure modes (`NoConcatenate`, `Count()` arguments, `QUALIFY` with prefixed fields, `DROP TABLE` discipline, `NullAsValue` scope)

Pair this with the inline summary in `SKILL.md` Section 1 (the "what" table) — this file covers the "why" and the worked examples.

## 1. SQL Constructs That Do Not Exist in Qlik LOAD

Using any of these in a `LOAD` or `RESIDENT` statement produces a reload error or silent data failure.

| SQL Construct | Why It Fails | Qlik Alternative |
|---|---|---|
| `HAVING` | Not a keyword in Qlik script | Preceding LOAD with `WHERE` on the aggregated field |
| `Count(*)` | No wildcard aggregation; `Count()` requires an explicit expression | `Count(field_name)` for non-null counts; `NoOfRows('TableName')` for row counts |
| `SELECT DISTINCT` | `SELECT` is for SQL pass-through to databases only | `LOAD DISTINCT` (the `LOAD` keyword, not `SELECT`) |
| `IS NULL` / `IS NOT NULL` | Operator syntax not supported in script | `IsNull(field)` / `NOT IsNull(field)` (function form) |
| `BETWEEN` | Not a keyword | `field >= low AND field <= high` |
| `IN (list)` | Not supported | `Match(field, val1, val2, ...)` (exact) or `WildMatch(field, ...)` (pattern) |
| `CASE WHEN` | Not a keyword | `IF()`, `Pick()`, or `Match()` inside a LOAD |
| `LIMIT` | Not a keyword | `FIRST n LOAD ...` prefix (works on any source); `WHERE RecNo() <= N` as a fallback for RESIDENT |
| Table aliases (`FROM table t1`) | Not supported in LOAD | Full table names in square brackets; no alias |

### The `SQL SELECT` pass-through exception

`SQL SELECT` statements directed at database connections (typically via `LIB CONNECT TO`) are handed off to the database engine, which interprets them in its native dialect. **Inside `SQL SELECT`, all of the above SQL syntax is valid** — `HAVING`, `Count(*)`, `BETWEEN`, `IN`, `CASE WHEN`, table aliases, `LIMIT`/`TOP`/`FETCH` (per the database dialect), and so on.

The constraint applies only to `LOAD` and `RESIDENT` operations executed by the Qlik script engine itself.

```qlik
// Valid: native SQL inside a SQL SELECT pass-through
LIB CONNECT TO [lib://SourceDB];
SQL SELECT
    customer_id,
    Count(*) AS order_count
FROM orders
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
  AND status IN ('Active', 'Pending')
GROUP BY customer_id
HAVING Count(*) > 5;

// Invalid: same SQL syntax in a Qlik LOAD/RESIDENT
[OrderSummary]:
LOAD customer_id, Count(*) AS order_count   // FAILS: Count(*) and HAVING are not script syntax
RESIDENT [Orders]
WHERE order_date BETWEEN '2026-01-01' AND '2026-12-31'
GROUP BY customer_id
HAVING Count(*) > 5;
```

The Qlik equivalent is a preceding LOAD with `WHERE` on the aggregated field:

```qlik
[OrderSummary]:
LOAD customer_id, order_count
WHERE order_count > 5;
LOAD customer_id, Count(order_id) AS order_count
RESIDENT [Orders]
WHERE Match(status, 'Active', 'Pending')
  AND order_date >= MakeDate(2026,1,1)
  AND order_date <= MakeDate(2026,12,31)
GROUP BY customer_id;
```

## 2. Additional Failure Modes

These five patterns are the next most common sources of reload failures and silent data corruption after the SQL-syntax issues above.

### 2.1 NoConcatenate on auto-concatenation risk

When a new `LOAD` produces a field set that matches an existing table exactly (same names AND same field count), Qlik silently concatenates the new rows into the existing table. The new table name is never registered: `NoOfRows('NewTable')` returns NULL, and `DROP TABLE [NewTable]` fails.

Always use `NoConcatenate` on temp tables that dedup, filter, or pivot existing data:

```qlik
[_TempA]: LOAD key FROM source;
[_TempB]: NoConcatenate LOAD DISTINCT key RESIDENT [_TempA];
DROP TABLE [_TempA];
```

`INLINE` LOADs trigger the same rule: two `LOAD * INLINE` blocks with identical column structures auto-concatenate even though they look visually distinct in source. The typical symptom is a later `RESIDENT [SecondTable]` failing with "table not found." Fix by adding a discriminator column or by prefixing with `NoConcatenate`.

Mapping tables are exempt from this rule (they are consumed at `ApplyMap()` time and don't appear in the data model).

Reference: help.qlik.com Cloud — Concatenate / NoConcatenate statements.

### 2.2 Count() requires an explicit expression — no `Count(*)`

`Count(*)` does not exist in Qlik LOAD or chart expressions. The `Count()` signature requires an explicit field or expression argument. The SQL `Count(*)` convention is only valid inside `SQL SELECT` pass-through statements (which Qlik hands off to the database engine).

In Qlik `LOAD` / `RESIDENT` context:

- **Count non-null values in a field:** `Count(field_name)`.
- **Count distinct values in a field:** `Count(DISTINCT field_name)`.
- **Count NULL values in a field:** `NullCount(field_name)`.
- **Count all rows in a loaded table:** `NoOfRows('TableName')` after the LOAD.

For clarity, prefer `Count(field_name)` over `Count(<literal>)` so the countable field is explicit. The SQL `Count(*)` convention is invalid in Qlik LOAD context — use `NoOfRows()` for row counts.

A widely-recommended community pattern is to add an explicit counter field during the load (`1 AS [Order.Counter]`) and use `Sum([Order.Counter])` downstream. This avoids ambiguity over which field/table is being counted, especially in associative chart context, and reduces engine work.

Avoid `Count()` directly on key fields: when a key links two tables, the engine cannot determine which table the count should run against, and the result is ambiguous.

### 2.3 QUALIFY / UNQUALIFY with already-prefixed fields

`QUALIFY *` prefixes every field with its table name to prevent unintended associations. If fields are already entity-prefixed by the naming convention (e.g., `Order.Status`, `Product.Category`), applying `QUALIFY *` creates double-prefixed fields (`TableName.Order.Status`) — breaking downstream field references and creating unintended synthetic keys.

**Rule:** Skip `QUALIFY` entirely when fields are already entity-prefixed. The naming convention has already prevented the ambiguity that `QUALIFY` exists to solve. Document the omission with a brief comment so the next reader doesn't add `QUALIFY` back.

**If `QUALIFY` is used:** it is a stateful toggle that affects every subsequent `LOAD` until `UNQUALIFY *` is called. Always `UNQUALIFY` the keys you need to associate on, immediately after `QUALIFY *`:

```qlik
QUALIFY *;
UNQUALIFY [%Customer.Key], [%Order.Key];   // keep keys associating
// ... table loads ...
UNQUALIFY *;                                // reset
```

Forgetting to `UNQUALIFY` the keys is silent — no error, no warning, just a data model with no associations.

See `qlik-naming-conventions` for the entity-prefix convention that obviates `QUALIFY` in most modern Qlik apps.

### 2.4 DROP TABLE discipline for temp tables

Every table prefixed with `_` (the temp-table convention) must have a corresponding `DROP TABLE`. Missing drops cause memory bloat and can trigger reload timeouts on large datasets.

```qlik
[_Staging]: LOAD ... FROM ... ;
// ... use _Staging to build mapping tables, resident loads, etc. ...
DROP TABLE [_Staging];
```

Mapping tables created with `MAPPING LOAD` are consumed at `ApplyMap()` time and auto-dropped — do NOT manually drop them. Attempting to `DROP TABLE` a mapping table fails.

### 2.5 NullAsValue scope persistence and key corruption

`NullAsValue` is field-specific and stateful — it persists across all subsequent LOADs until explicitly reset with `NullAsNull *` and `SET NullValue=;`.

Two failure modes:

1. **Key field corruption.** Applying `NullAsValue` to key fields converts NULL to a string value (e.g., `'No Entry'`). Every NULL key in the source becomes the same string — creating phantom associations between unrelated rows (a customer with a NULL region key and an order with a NULL region key now "match" through the substituted string).
2. **Measure field corruption.** Applying `NullAsValue` to measure fields converts NULL to a string. `Sum(field)` then silently breaks because the field is no longer numeric for the substituted rows.

Always reset immediately after the LOAD that needed null substitution:

```qlik
SET NullValue = 'No Entry';
NullAsValue [Dimension.Category];

[Dimension]:
LOAD id, name AS [Dimension.Name], category AS [Dimension.Category]
FROM source;

// Reset immediately:
NullAsNull *;
SET NullValue =;

// Now safe to load other tables without NullAsValue interference.
```

Use `NullAsValue` ONLY on sparse dimension fields (text fields with many NULLs that should display as "No Entry" in filter panes). For string-encoded nulls ("null", "NaN", "n/a"), use `vCleanNull` instead — see `null-handling.md`.

## See Also

- `qlik-load-script` SKILL.md Section 1 — inline summary table.
- `qlik-load-script` SKILL.md Section 14 — NoConcatenate full treatment with the INLINE auto-concat trap.
- `null-handling.md` — canonical script-layer null handling (Null/IsNull/NullCount, vCleanNull, NullAsValue brief, key-field NULL, date sentinel guards, decision framework).
- `qlik-naming-conventions` — entity-prefix convention that obviates `QUALIFY`.
- help.qlik.com Cloud — Aggregation functions (Count, NullCount), Concatenate / NoConcatenate, NullAsValue.
