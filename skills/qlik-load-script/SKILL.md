---
name: qlik-load-script
description: "Script syntax reference, QVD optimization, incremental load patterns (insert-only, insert/update, insert/update/delete, dual-timestamp for SCD2), JOIN/KEEP prefixes, ApplyMap patterns, CROSSTABLE, master calendar generation, variable definitions, error handling, logging patterns, null handling patterns, diagnostic and validation patterns, subroutine integration, and platform gotchas (SET vs LET, dollar-sign expansion timing, SET variable comma limitation). Load when writing, reviewing, or debugging Qlik load scripts, QVD operations, STORE/LOAD syntax, preceding LOAD, NullAsValue, script organization, JOIN, KEEP, ApplyMap, CROSSTABLE, AutoNumber, composite keys, or data quality defensive coding."
user-invocable: false
---

# Qlik Load Script

Qlik script resembles SQL but is a fundamentally different language. It runs inside the Qlik associative engine, not a relational database. The most critical rule: **Qlik script is NOT SQL.** The single most predictable failure mode for AI-generated scripts is SQL syntax inside LOAD statements. Before writing any LOAD statement, internalize Section 1 below. Before writing any variable function, internalize Section 3.

This skill covers script mechanics, QVD operations, incremental loads, null handling, error handling, diagnostics, variable patterns, master calendar, and subroutine integration. It does NOT cover naming conventions (see `qlik-naming-conventions`), data model design (see `qlik-data-modeling`), expression syntax (see `qlik-expressions`), or optimization strategies (see `qlik-performance`).

## 1. Script Generation Constraints (CRITICAL)

These SQL constructs do NOT exist in Qlik LOAD statements. Using them causes reload errors or silent failures.

| SQL Syntax | Why It Fails | Qlik Alternative |
|---|---|---|
| `HAVING` | Not a keyword in Qlik script | Preceding LOAD with `WHERE` on aggregated field |
| `Count(*)` | No wildcard aggregation | `Count(field_name)` with explicit field |
| `SELECT DISTINCT` | SELECT is for SQL pass-through only | `LOAD DISTINCT` |
| `IS NULL` / `IS NOT NULL` | Operator syntax not supported | `IsNull(field)` / `NOT IsNull(field)` |
| `BETWEEN` | Not a keyword | `field >= low AND field <= high` |
| `IN (list)` | Not supported | `Match(field, v1, v2)` or `WildMatch()` |
| `CASE WHEN` | Not a keyword | `IF()`, `Pick()`, or `Match()` |
| `LIMIT` | Not a keyword | `FIRST n LOAD ...` prefix (works on any source); `WHERE RecNo() <= N` as a fallback |
| Table aliases (`FROM t1`) | Not supported in LOAD | Full table names in brackets |

**Exception:** `SQL SELECT` pass-through statements to database connections CAN use native SQL syntax including all of the above. The constraint applies only to LOAD/RESIDENT operations.

**Dollar-sign expansion safety:** Every `$(variable(...))` call must be checked for commas in arguments. Inside `$()`, commas separate parameters, not expression arguments. See Section 3 for the full rules and examples.

**Deeper reference:** see `references/sql-constructs.md` for each construct's full failure mode, worked-example rewrites of the SQL→Qlik conversion, the `SQL SELECT` pass-through exception with examples, and the five most common adjacent failure modes (`NoConcatenate`, `Count()` argument requirements, `QUALIFY` with prefixed fields, `DROP TABLE` discipline, `NullAsValue` scope).

### QUALIFY/UNQUALIFY

`QUALIFY` prefixes field names with their table name to prevent unintended associations. It is one way to avoid synthetic keys, but aliasing fields with `AS` in the LOAD is equally valid and usually clearer. `QUALIFY` is a stateful toggle — forgetting to `UNQUALIFY` the keys you need to associate on results in a silent data model with no associations. If fields are already entity-prefixed by the naming convention, `QUALIFY *` produces double-prefixed names (`TableName.Customer.Name`) — skip `QUALIFY` entirely in that case. Full treatment with worked examples in `references/sql-constructs.md` Section 2.3.

## 2. SET vs LET

`SET` preserves the right side as literal text (a template). `LET` evaluates the right side immediately.

```qlik
// SET preserves the template -- $1 placeholders stay unevaluated:
SET vDualBool = IF(Match($1, 'true') > 0, Dual('$2', 1), Dual('$3', 0));

// LET evaluates immediately -- use for computed values:
LET vRowCount = NoOfRows('MyTable');
LET vToday = Num(Today());
```

**Rule:** Use `SET` for variable functions containing quotes, Dual(), or `$1` placeholders. Use `LET` for simple value assignments where you need the result now.

**Critical:** `SET` does not evaluate function calls. `SET HidePrefix=Chr(37);` assigns the literal string `Chr(37)`, not the `%` character. To assign a computed value, use `LET HidePrefix=Chr(37);` or `SET HidePrefix='%';`. This applies to all function calls on the right side of SET, including `Chr()`, `Num()`, `Date()`, `Today()`, `Time()`, etc.

## 3. Dollar-Sign Expansion

Inside `$()`, commas are parameter delimiters. This is the #1 source of reload errors in scripts using SET variable functions.

```qlik
// The comma in PurgeChar breaks the variable call:
// WRONG: $(vCleanNull(PurgeChar(field, '[]')))
// The engine sees: $1=PurgeChar(field, $2='[]')

// RIGHT -- write inline with comment:
// Cannot use vCleanNull here (comma in PurgeChar args)
IF(IsNull(PurgeChar(given_names, '[]{}' & Chr(34)))
   OR Len(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))) = 0,
   Null(),
   Trim(PurgeChar(given_names, '[]{}' & Chr(34))))  AS [Name.Given]
```

Only pass simple field names or literals (no commas) as arguments to variable functions.

**Null variable expansion:** If a `LET` assignment evaluates to null, the variable is empty. `IF $(emptyVar) >= 0 THEN` becomes `IF >= 0 THEN` -- a syntax error. Guard at assignment time with a default: `LET vX = Alt(NoOfRows('MaybeGone'), -1);` or check before expansion: `IF '$(vX)' <> '' AND $(vX) >= 0 THEN`. This applies to any function that can return null (`NoOfRows` on dropped/nonexistent tables, `Peek` past end of table, `FieldValue` out of range, etc.).

## 4. Preceding LOAD

Two LOAD statements sharing one source. The inner (bottom) LOAD executes first. The outer (top) LOAD reads the inner's output and can reference fields calculated by the inner -- so you only write the expensive expression once.

```qlik
[Customers]:
LOAD
    *,
    IF([Customer.TenureYears] < 1, 'New', 'Returning') AS [Customer.TenureBand]
;
LOAD
    customer_id AS [Customer.Key],
    customer_name AS [Customer.Name],
    registration_date,
    Floor((Today() - registration_date) / 365.25) AS [Customer.TenureYears]
FROM [lib://QVDs/Customers.qvd] (qvd);
```

The bottom LOAD pulls from the QVD and computes `[Age]`. The top LOAD reads those rows and references `[Age]` to derive `[Age.Category]`. Only one table (`[Customers]`) is produced. The same pattern works with `RESIDENT`, `INLINE`, and `SQL SELECT` sources.

**When to use:** Avoid repeating the same complex expression in nested IFs. Calculate once in the inner LOAD, reference in the outer. Also used as the Qlik replacement for `HAVING`: aggregate in inner LOAD, filter on the aggregate in outer LOAD with `WHERE`.

## 5. Date/Number Interpretation

Qlik stores every value as a **dual**: a text representation and a numeric representation held together. Dates are stored as serial numbers (days since 1899-12-30). Understanding this dual nature prevents the most common date bugs.

**`Date#()` vs `Date()`:** `Date#(string, 'format')` interprets a text string into its numeric serial value (parsing). `Date(serial, 'format')` formats a numeric serial into a display string. Confusing them is the #1 date bug.

```qlik
// Interpreting a text date from source:
Date#(ship_date, 'MM/DD/YYYY') AS [Order.ShipDate]

// Formatting an already-numeric date for display:
Date(Floor(order_timestamp), 'YYYY-MM-DD') AS [Order.Date]
```

**SET DateFormat dependency:** `Date#()` without a format argument uses the app's `SET DateFormat`. If source dates differ from the app format, you MUST specify the format string explicitly. Silent misinterpretation produces wrong dates with no error.

**Num#() and Num():** Same pattern. `Num#(string, 'format')` parses text to number. `Num(number, 'format')` formats for display. For money: `Num#(revenue, '#,##0.00')`.

## 6. Null Handling (Summary)

Three strategies, each for a different scenario:

**vCleanNull variable function:** For string-encoded nulls ("null", "NaN", "n/a", "[null]") from ETL pipelines and data lakes. `IsNull()` does NOT catch these. See `null-handling-patterns.md` and `script-templates/clean-null-function.qvs`.

**NullAsValue:** For sparse dimension fields where NULL should display as "No Entry" in filter panes. Field-specific and stateful (persists until reset). Field names must match OUTPUT aliases, not source names. Never use on key fields (breaks associations) or measure fields (breaks Sum/Avg). See `null-handling-patterns.md`.

**Null guards on date arithmetic:** Genuine NULL dates propagate correctly (`Today() - NULL = NULL`), so the real threat is non-NULL sentinel dates (`1900-01-01`, `1970-01-01`, epoch zero) that upstream systems substitute for missing values -- these produce plausible-looking but wrong ages. Guard date math against BOTH null and out-of-range sentinels: `IF(IsNull(d) OR d < MakeDate(1901,1,2) OR d > Today(), Null(), ...)`. See `null-handling-patterns.md`.

**Decision framework:**
| Field Type | Strategy |
|---|---|
| String dimensions from external sources | vCleanNull |
| Sparse dimensions for filter pane display | NullAsValue |
| Date/numeric calculations | Explicit IsNull guards |
| Key fields | Never mask nulls (they indicate data quality issues) |

## 7. Data-Driven Patterns

**Range bucketing via mapping expansion:** Replace nested IFs with inline data + mapping table + ApplyMap. Edit the inline table to change buckets, no code changes needed.

```qlik
[_Def]: LOAD * INLINE [from, to, label, sort
0,  17, 0-17,  1
18, 24, 18-24, 2
65, 200, 65+,  7] (delimiter is ',');

_Map: MAPPING LOAD Num#(from) + IterNo() - 1, Dual(Trim(label), Num#(sort))
RESIDENT [_Def] WHILE Num#(from) + IterNo() - 1 <= Num#(to);
DROP TABLE [_Def];

ApplyMap('_Map', [Age], Dual('Unknown', 0)) AS [Age.Group]
```

**Boolean fields via Dual:** `Dual('Active', 1)` enables text display AND numeric aggregation (`Sum([Is.Active])` = count of active). Wrap in a SET variable function for reuse. See `script-templates/clean-null-function.qvs` for vDualBool.

**Metadata-driven table loading:** Define an inline metadata table (TableName, SourceTable, PrimaryKey, Enabled) and loop through it with FOR/Peek. Adding a new table = adding a metadata row.

```qlik
FOR i = 0 TO NoOfRows('_Metadata') - 1
    LET vTableName = Peek('TableName', $(i), '_Metadata');
    LET vEnabled   = Peek('Enabled', $(i), '_Metadata');
    IF '$(vEnabled)' = 'Y' THEN
        [$(vTableName)]:
        LOAD * FROM [lib://Connection/$(vTableName).qvd] (qvd);
    END IF
NEXT i
```

**Concat-and-Peek for UI-variable build:** Materialize a delimited string (typically `|`-separated tokens) once at reload and expose it via a variable. The common consumer is the Dashboard Bundle Variable Input control, whose Dynamic values mode parses a pipe-delimited string rather than enumerating a field — a bare field reference in that control collapses to one scalar.

```qlik
[_PipeBuild]:
LOAD Concat([Code] & '~' & [Label], '|') AS pipe RESIDENT [Menu];
LET vPipe = Peek('pipe', 0, '_PipeBuild');
DROP TABLE [_PipeBuild];
```

Consume on the UI side with dollar-sign expansion (`='$(vPipe)'`). The technique generalizes beyond Variable Input — anywhere a UI control or set-analysis clause needs a delimited string of distinct values, this is the pattern. See `qlik-visualization` → `references/variable-input-control.md` for the full UI consumption walkthrough including value-label form and chart-side double-dollar dereferencing.

## 8. JOIN/KEEP Prefixes

JOIN and KEEP combine two tables. **Critical difference from SQL:** Qlik joins on ALL fields with matching names between the two tables, not just the field you intend as a key. Unintended field-name overlaps produce wrong results silently.

**Worked example of the silent collision:**

```qlik
// Customers has: CustomerID, Name, Status, Region
// Orders has:    OrderID, CustomerID, OrderDate, Amount, Status
// BOTH tables have a 'Status' field -- a silent collision waiting to happen.

// WRONG -- Qlik will join on BOTH CustomerID AND Status:
[Customers]: LOAD CustomerID, Name, Status, Region FROM [customers.qvd] (qvd);
LEFT JOIN([Customers])
LOAD OrderID, CustomerID, OrderDate, Amount, Status FROM [orders.qvd] (qvd);
// Result: orders only attach to customers where Status matches too.
// A customer with Status='Active' and an order with Status='Shipped'
// will NOT match. The LEFT JOIN silently drops those orders.

// RIGHT -- alias the overlapping non-key field before the join:
[Customers]:
LOAD CustomerID, Name, Status AS [Customer.Status], Region
FROM [customers.qvd] (qvd);

LEFT JOIN([Customers])
LOAD OrderID, CustomerID, OrderDate, Amount, Status AS [Order.Status]
FROM [orders.qvd] (qvd);
// Now CustomerID is the only shared field and the only join criterion.
```

**The rule:** Before any JOIN, list the fields in both tables and alias every non-key field that shares a name. Never rely on Qlik to "figure out" the intended key.

```qlik
// LEFT JOIN adds lookup fields to the main table (rows preserved):
LEFT JOIN([Orders])
LOAD [%Customer.Key], [Customer.Region]
RESIDENT [Customers];

// INNER JOIN retains only matching rows:
INNER JOIN([Orders])
LOAD DISTINCT [%Customer.Key] RESIDENT [ActiveCustomers];
```

**JOIN vs KEEP:** JOIN merges into one table (matched fields combined). KEEP filters both tables to matching rows but keeps them as separate tables in the data model. Use KEEP when you want association filtering without merging.

**Row multiplication:** If the join key is not unique in both tables, rows multiply. A 1000-row fact joined to a lookup with 3 rows per key produces 3000 rows. Always ensure the lookup side has unique keys, or use ApplyMap instead.

**Decision framework:** JOIN for small lookups with unique keys. ApplyMap for large lookups or when you need a default value (see Section 9). Let the associative engine handle dimension-to-fact relationships naturally (no join needed). See `qlik-performance` for JOIN vs ApplyMap benchmarks.

## 9. ApplyMap Patterns

ApplyMap performs a key-value lookup from a mapping table. Faster than JOIN for large datasets and safer (no row multiplication, provides a default for unmatched keys).

```qlik
// Create mapping table (two-column: key, value):
[_RegionMap]: MAPPING LOAD [%Customer.Key], [Customer.Region]
RESIDENT [Customers];

// Apply in a LOAD statement:
ApplyMap('_RegionMap', [%Customer.Key], 'Unknown') AS [Customer.Region]
```

**Critical gotcha -- never alias the result with the same name as the lookup field:**

```qlik
// WRONG -- silently replaces the code with the mapped name:
LOAD
    OrderID,
    ApplyMap('_RegionMap', RegionCode, 'Unknown') AS RegionCode  // BUG
FROM ...;
// Result: RegionCode column now contains 'North America', 'Europe', etc.
// The original codes are permanently lost. Any downstream table or
// association that still expects codes in RegionCode is now broken.

// RIGHT -- alias the result to a distinct name:
LOAD
    OrderID,
    RegionCode,                                                    // keep the code
    ApplyMap('_RegionMap', RegionCode, 'Unknown') AS [Region.Name] // add the label
FROM ...;
```

The Qlik script engine does not raise an error for the broken form. Both the input and output resolve to the same field name, and the ApplyMap result wins -- silently replacing the raw code values. Always give the ApplyMap output a distinct alias (typically the `.Name` or `.Label` suffix) so the original key field remains intact.

**MAP...USING vs ApplyMap:** `MAP...USING` applies a mapping automatically to every subsequent LOAD of the named field. `ApplyMap` is explicit, per-expression. Prefer ApplyMap for clarity; use MAP...USING only for global, consistent field translations (e.g., country code to country name everywhere). See `qlik-performance` for ApplyMap optimization on large datasets.

## 10. QVD Operations (Summary)

**STORE:** `STORE * FROM [TableName] INTO [lib://Connection/file.qvd] (qvd);` -- one table per STORE.

**Optimized vs standard read:** Optimized read is ~10x faster than standard. Preserved by `LOAD *`, field subsetting, `AS` renaming, `LOAD DISTINCT`, `CONCATENATE`, and **one-parameter** `EXISTS(field)`. Forced to standard by any field transform, derived fields, two-parameter `EXISTS(field, expression)`, WHERE clauses other than one-parameter EXISTS, or `Map...Using`.

**Load once, map many:** Never read the same QVD from disk twice. Load to a temp table, build all MAPPING tables `RESIDENT [_Temp]`, then `DROP TABLE [_Temp]`.

**Binary load:** `binary [app];` must be the FIRST statement (before SET). Loads data tables and section access only. One per script.

See `qvd-operations.md` for complete read-mode details with worked examples.

## 11. Incremental Load Patterns (Summary)

| Source Pattern | Strategy | Key Requirement |
|---|---|---|
| Append-only transactions | Insert-only (by timestamp/key) | Monotonic key or reliable timestamp |
| Mutable dimension (SCD1) | Insert/update (by ModifiedDate) | Reliable modification timestamp |
| Full-refresh staging | Full replace each cycle | None |
| SCD Type 2 dimension | **Dual-timestamp** (effective_from + effective_to) | Both timestamps tracked |
| Mutable with deletes | Insert/update/delete | Change detection + deletion flag or full-key comparison |

**Critical:** The dual-timestamp SCD Type 2 pattern must capture BOTH newly created records AND records whose effective_to changed (previously current records that were closed). Missing the closure condition = silent data loss. See `incremental-load-patterns.md` for complete working code and `script-templates/dual-timestamp-incremental.qvs` for the ready-to-use template.

## 12. Master Calendar

A master calendar provides a continuous date dimension with custom periods (fiscal year, relative date flags). It must derive date ranges from loaded data, never hard-coded. Must produce Dual-sorted month fields for correct sort with text display.

**Dual() for chronological month sort -- critical pattern:**

Plain `Month(date)` returns a text value ("Jan", "Feb"...) which sorts alphabetically (Apr, Aug, Dec, Feb...) in charts. Wrap every month-like field in `Dual(text, number)` so the text displays correctly AND the numeric component drives the sort order:

```qlik
// WRONG -- sorts alphabetically:
Month([Order.Date]) AS [Cal.Month]

// RIGHT -- displays "Jan" but sorts as 1:
Dual(Month([Order.Date]), Num(Month([Order.Date]))) AS [Cal.Month]

// For year-month labels in time-series charts:
Dual(Date(MonthStart([Order.Date]), 'MMM-YYYY'),
     Year([Order.Date]) * 100 + Num(Month([Order.Date]))) AS [Cal.MonthYear]
```

Apply the same pattern to weekday, quarter, and fiscal period fields. Without Dual(), charts and filter panes will display months alphabetically even when the MonthNum field exists separately.

**Fiscal year configuration:** Set `vFiscalYearStartMonth` (e.g., 7 for July start). The template handles the year offset automatically: FY2026 runs Jul 2025 - Jun 2026 when start=7.

**Multiple date fields:** If your model has Order.Date, Ship.Date, and Invoice.Date, choose one primary date as the calendar key. Other dates filter via set analysis. Alternatively, create separate calendar tables with prefixed fields (OrderCal.Year, ShipCal.Year) for direct filtering on any date.

**Relative date flags:** The template includes IsCurrentMonth, IsCurrentYear, IsPriorYear, IsYTD, IsPriorYTD, IsRolling12, and IsToday. These enable period-over-period comparisons without set analysis.

See `script-templates/master-calendar.qvs` for the production-ready template.

## 13. Error Handling and Logging

- **TRACE:** `TRACE === Phase: Extract ===;` for milestones. `TRACE Rows loaded: $(vRowCount);` for row counts.
  - **Semicolons inside the message text are consumed by the parser unless the whole text is quoted.** Qlik treats `;` as the statement terminator outside any quoted string, and TRACE accepts an unquoted argument by default — so a bare `;` in the message ends the statement early and the words that follow parse as an unknown statement. Two safe options: (a) use commas, periods, or dashes as in-text separators; (b) wrap the entire trace text in single quotes so the `;` sits inside a string literal. WRONG: `TRACE Loaded $(vRows); see diagnostics for detail;`. RIGHT (a): `TRACE Loaded $(vRows). See diagnostics for detail;` or `TRACE Loaded $(vRows) -- see diagnostics for detail;`. RIGHT (b): `TRACE 'Loaded $(vRows); see diagnostics for detail';`. Treat TRACE text the way you'd treat any other Qlik string argument — when in doubt, quote it.
- **ScriptError vs ScriptErrorCount -- do not confuse these:**
  - `ScriptError` is a **dual value** (numeric error code + text component) reflecting only the **most recent statement**. It is reset to 0 after every successfully executed statement. Because it resets, it cannot detect errors across multiple operations -- only the immediately preceding one.
  - `ScriptErrorCount` is an **integer counter** that is **cumulative** across the entire reload. It increments with each failed statement and is never reset mid-reload.
  - For per-operation error detection across multiple statements, snapshot the count: `LET vPreErrors = ScriptErrorCount;` before an operation and compare `IF ScriptErrorCount > $(vPreErrors)` after. A plain `IF ScriptErrorCount > 0` check after the second operation returns true even if only the first operation failed. See `script-templates/error-handling.qvs` for the correct pattern.
- **ScriptErrorList:** Concatenated list of all errors, line-feed separated. Use for logging.
- **ErrorMode:** `SET ErrorMode = 1;` is the default in Qlik Sense and Qlik Cloud.
  - `ErrorMode = 0` -- ignore the failure and continue the script. Useful for non-critical fallback paths but requires careful `ScriptErrorCount` checking to detect problems.
  - `ErrorMode = 1` (default) -- halt the script on error. In interactive QlikView this prompts the user; in Qlik Sense/Cloud batch reloads this stops the reload.
  - `ErrorMode = 2` -- immediately trigger an "Execution of script failed" error and stop, with no user prompt even in interactive contexts. Use when you want hard-stop semantics regardless of environment.
- **File existence:** `IF NOT IsNull(FileTime('lib://path/file.qvd')) THEN` to check before loading.
- **Field value inspection at script time:** To get min/max of a loaded field, use a Resident LOAD: `[_Temp]: LOAD Min(Field) AS _min, Max(Field) AS _max Resident MyTable; LET vMin = Peek('_min', 0, '_Temp'); DROP TABLE [_Temp];`. For symbol table iteration, use `FieldValue('Field', n)` with `FieldValueCount('Field')`. Note: `fieldvaluelist` is a `FOR EACH` loop keyword (like `filelist` and `dirlist`), not a general-purpose function -- it cannot be used in LET assignments or as an argument to other functions.

See `script-templates/error-handling.qvs` for the error handling and logging framework (preferred for production scripts). See `diagnostic-patterns.md` for standalone TRACE templates and validation queries. **These are alternatives, not complements.** If using error-handling.qvs, use its `LogRowCount` subroutine. The standalone `LogLoadCount` in diagnostic-patterns.md is for scripts that don't include the full framework.

## 14. NoConcatenate and Auto-Concatenation

When a new LOAD produces a field set identical to an existing table's (same names AND same count), Qlik silently concatenates the rows into the existing table — the new table name is never registered. The basic `NoConcatenate` pattern, the convention to apply it defensively on temp tables, and the broader failure-mode context live in `references/sql-constructs.md` Section 2.1.

**INLINE LOADs trigger the same rule.** Two `LOAD * INLINE` blocks with identical column structures auto-concatenate even though they look visually distinct in source. The second table name is silently lost; a later `RESIDENT [SecondTable]` fails with "table not found" — the typical symptom that surfaces the trap. Fix either by adding a discriminator column or by prefixing the second LOAD with `NoConcatenate`.

```qlik
// BROKEN -- both INLINE blocks share columns, [MenuB] silently merges into [MenuA]:
[MenuA]:
LOAD * INLINE [Col1, Col2
A, B];

[MenuB]:
LOAD * INLINE [Col1, Col2
C, D];

// FIXED -- explicit NoConcatenate keeps them separate:
[MenuB]:
NoConcatenate
LOAD * INLINE [Col1, Col2
C, D];
```

**Explicit CONCATENATE prefix:** `CONCATENATE([TargetTable])` forces concatenation even when field sets differ. Mismatched fields get NULL in the target. Use when intentionally merging tables with partially overlapping schemas.

**Mapping LOAD tables are invisible to meta-functions.** Tables created via `Mapping LOAD` are consumed at `ApplyMap()` time and do not persist as named tables in the data model. `NoOfRows('MappingTableName')`, `FieldValueCount()`, `FieldName()`, and all other table/field meta-functions return null or -1 for Mapping tables. Validate indirectly by checking the row count of the downstream table that consumes the mapping (e.g., if the target table loads 0 rows, the mapping was likely empty or misconfigured).

Reference: help.qlik.com Cloud — Concatenate / NoConcatenate statements.

## 15. EXISTS Symbol Space Behavior

`EXISTS(field, value)` checks the **entire symbol space** (all tables with that field name), not one table. This includes values already loaded in the current statement.

**Cross-table contamination:** If `[Dimension]`, `[_TempA]`, and `[_TempB]` all have `key_field`, then `WHERE NOT EXISTS(key_field)` checks all three. This produces unexpected zero-row results.

**Self-referencing dedup (documented gotcha):** `WHERE NOT EXISTS(field)` using one-parameter form checks values that have already been loaded **during the current LOAD statement**, not just previously loaded tables. The symbol table updates row by row as the load progresses. When a value loads, it immediately becomes "existing." The next row with the same value sees it as already existing and is skipped. Result: only the **first occurrence** of each value loads. This is intentional Qlik behavior but often unintended by the developer.

```qlik
// Only loads ONE row per customer_id, even if source has duplicates:
LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS(customer_id);

// To load ALL rows for non-existing keys, alias the lookup field
// so the current load's values don't pollute the check:
[_Existing]:
LOAD DISTINCT customer_id AS _existing_cust RESIDENT [Customers];

LOAD * FROM [lib://QVDs/Orders.qvd] (qvd)
WHERE NOT EXISTS(_existing_cust, customer_id);

DROP TABLE [_Existing];
```

**Workaround for both issues:** Load the lookup field into a separate table under a different alias, then use the two-parameter form: `WHERE NOT EXISTS(aliased_field, source_field)`. This avoids self-referencing dedup AND cross-table contamination. Note that the two-parameter form forces standard QVD read mode.

## 16. CROSSTABLE Prefix

CROSSTABLE unpivots columnar data into normalized rows. Common when loading Excel pivot tables or wide-format source data.

```qlik
// Source has: Product, Jan, Feb, Mar (with sales values in month columns)
// Result: Product, Month, Sales (one row per product-month combination)
CROSSTABLE(Month, Sales, 1)
LOAD * FROM [lib://Data/SalesPivot.xlsx] (ooxml, embedded labels, table is Sheet1);
```

**Syntax:** `CROSSTABLE(AttributeField, DataField, NoOfQualifyingFields)`. The third parameter specifies how many left-side columns to keep as-is (qualifying columns). All remaining columns become attribute-value pairs. If your source has `Region, Product, Jan, Feb, Mar`, use `NoOfQualifyingFields = 2` to keep Region and Product as row identifiers.

## 17. AutoNumber and Composite Keys

**Composite key pattern:** Concatenate multiple fields with a delimiter to create a synthetic key. Use a safe delimiter that cannot appear in the data.

```qlik
[%Region.Product.Key]: [Region] & '|' & [Product] AS [%Region.Product.Key]
```

**AutoNumber:** Replaces a field's values with sequential integers for memory optimization. Reduces RAM by eliminating long string keys from the symbol table.

```qlik
AutoNumber([%Region.Product.Key], '%Region.Product.Key');
```

**Critical warning:** AutoNumber numbering depends on load order. Per help.qlik.com: "You can only connect autonumber keys that have been generated in the same data load, as the integer is generated according to the order the table is read." Consequences:
- The same business value receives different integers if the load order changes (added/removed source rows, changed sort, different reload sequence).
- AutoNumber values are NOT stable across apps or across reloads. Never use them as persistent identifiers, foreign keys to other apps, or in inter-app data exchange.
- If you need stable keys across reloads or apps, use `Hash128`/`Hash160`/`Hash256` on the business key instead -- Qlik help explicitly recommends this.

**Community best practice:** Apply AutoNumber only in the final app-level model load, not in the QVD extraction layer. The reasoning is twofold: (1) extracted QVDs may be consumed by multiple downstream apps, each of which would assign its own unrelated integers to the same business values, breaking associations; and (2) AutoNumber inside a LOAD FROM QVD forces standard (non-optimized) read mode, defeating the purpose of the extraction layer. This is widely held expert guidance (Rob Wunderlich, Henric Cronström) rather than a Tier-1 documented rule, but the underlying mechanisms are both documented.

## 18. Subroutine Integration

**Include external files:** `$(Must_Include=lib://Connection/path/file.qvs);` fails the reload if the file is missing. `$(Include=...)` silently skips.

**Call subroutines:** `CALL SubName(param1, param2);` after the include.

**Variable scoping:** Qlik variables are primarily global, with one exception documented by help.qlik.com:
- **Variables created inside a SUB with `LET` or `SET`** are global. They persist after the subroutine returns and will overwrite any caller variable of the same name.
- **Formal parameters declared in the SUB signature** (e.g., `SUB MySub(pArg1, pArg2)`) are locally scoped to that subroutine. Extra parameters beyond the actual arguments passed are initialized to NULL and can be used as local-only working variables.

Practical rule: use the SUB parameter list for anything that must not leak out, and use naming prefixes (e.g., `vSub_MySub_Counter`) for `LET`/`SET` variables that stay global. Never rely on a bare `LET` inside a SUB for local state.

**FOR EACH loops:** Iterate over file lists or value lists.
```qlik
FOR EACH vFile IN FileList('lib://Data/*.qvd')
    [_AllData]: LOAD * FROM [$(vFile)] (qvd);
NEXT vFile
```
Note: In Qlik Cloud, wildcard file paths (`*`) may not be supported in all connection types. Use a directory listing or explicit file names if wildcards fail.

**Phantom field prevention:** Some shared subroutines initialize empty inline tables. If column parameters are wildcards or improperly specified, phantom fields appear in results. Always verify subroutine output contains only expected fields. After calling a subroutine, check by iterating fields in script:

```qlik
FOR vFldIdx = 1 TO NoOfFields('$(vResultTable)')
    LET vFldName = FieldName($(vFldIdx), '$(vResultTable)');
    TRACE Field $(vFldIdx): $(vFldName);
NEXT vFldIdx
```

**Composite key workaround:** When a subroutine handles only single keys but you need composite keys, concatenate key parts before calling and split after, or bypass the subroutine and implement the logic directly.

## 19. Synthetic Keys

Synthetic keys occur when two or more tables share multiple field names. Qlik auto-generates a composite key (prefixed with `$Syn`) linking the tables. This is usually unintentional and can cause performance issues and ambiguous associations.

**Resolution strategies:** (1) Rename non-key overlapping fields with `AS` to make them unique per table. (2) Use QUALIFY/UNQUALIFY (Section 1). (3) Create an explicit composite key and remove the individual shared fields from one table. See `qlik-data-modeling` for data model design patterns that prevent synthetic keys.

## 20. LIB CONNECT TO

`LIB CONNECT TO [ConnectionName];` targets subsequent `SQL SELECT` statements at a specific data connection. Without it, SQL goes to whatever connection was last active.

```qlik
LIB CONNECT TO [lib://SourceDB];
SQL SELECT * FROM customers;
```

**lib:// path format:** All file and connection references in Qlik Sense/Cloud use `lib://` prefix. `FROM [lib://DataFiles/data.csv]` for files. The connection name in brackets must match the data connection name exactly (case-sensitive in Cloud).

**Cloud space-aware prefix:** In Qlik Cloud shared or managed spaces, the **space name comes before the colon** and the **connection name comes after**:

```qlik
// Correct Qlik Cloud space-aware syntax:
LOAD * FROM [lib://SalesSpace:DataFiles/orders.csv] (txt, delimiter is ',', embedded labels);
LIB CONNECT TO 'SalesSpace:OperationalDB';
```

The format is `lib://<SpaceName>:<ConnectionName>/...`. Reversing the order (`lib://DataFiles:SalesSpace/...`) fails to resolve the connection at reload. Personal space does not require a prefix; only shared and managed spaces use this syntax.

## 21. Script Organization

| Approach | When to Use |
|---|---|
| Tabs (in-app sections) | Simple single-app projects, all code visible in one editor |
| Include files (.qvs) | Multi-app projects, shared code, version control |
| Numeric prefix | `01_Config.qvs`, `02_Extract_SourceA.qvs`, `03_Transform.qvs` |

**Split when** a single tab exceeds ~500 lines. Split by logical function (config, extract per source, transform, model load, calendar, diagnostics).

**Script execution manifest:** A documentation file listing each script file, its purpose, dependencies, and run order.

## 22. Cross-Layer Field Rename Mechanics

Three mechanisms for renaming fields in scripts, from simple to systematic:

- **Aliasing in LOAD:** `source_field AS [UI.Field.Name]` -- use for per-field transforms during extraction or model load.
- **RENAME FIELD:** `RENAME FIELD old_name TO [New.Name];` -- use for individual post-load renames. **Collision warning:** RENAME FIELD affects ALL tables containing that field name. If `region` exists in both `[Customers]` and `[Products]`, `RENAME FIELD region TO [Customer.Region]` renames it in both tables. Use Mapping RENAME or aliasing in LOAD when you need table-specific renames.
- **Mapping RENAME:** Bulk rename from a mapping table. Use for systematic cross-layer renaming (e.g., all raw extract names to model-layer names in one operation). Same cross-table behavior as RENAME FIELD, so ensure source field names are unique across tables before applying.

```qlik
[_RenameMap]: MAPPING LOAD old_name, new_name INLINE [
old_name, new_name
acct_status, Customer.Status
ship_addr_line1, Customer.ShipAddress
] (delimiter is ',');
RENAME FIELDS USING [_RenameMap];
```

See `qlik-naming-conventions` for the naming strategy (what names to use at each layer).

## 23. Placeholder Logic for Blocked Dependencies

When a source table is unavailable, produce a documented empty table with the expected schema so the pipeline continues. Every placeholder must include: what it replaces, expected source, resolution condition, and a TRACE warning.

```qlik
// PLACEHOLDER: Product loyalty data not yet available
// Source: loyalty_program.product_affinity (via lib://LoyaltyDB)
// Resolves when: Loyalty team delivers API access (ETA: Q2 2026)
TRACE [WARNING] Using placeholder for Product.Loyalty -- source not available;
[ProductLoyalty]:
LOAD * INLINE [
    Product.Key, Loyalty.Tier, Loyalty.Points
] (delimiter is ',');
```

## 24. String Functions

**PurgeChar** strips multiple characters in one call. Always requires two arguments:
```qlik
// WRONG -- missing second argument:
PurgeChar(my_field)
// RIGHT:
PurgeChar(my_field, '[]{}' & Chr(34))
```

**SubField + IterNo** for array expansion:
```qlik
LOAD key_field,
    Trim(SubField(clean_list, ',', IterNo())) AS [Expanded.Value]
RESIDENT [Source]
WHILE Len(Trim(SubField(clean_list, ',', IterNo()))) > 0;
```

Clean delimiters with PurgeChar before expanding.

## Supporting Files

- `references/sql-constructs.md` -- SQL constructs not valid in Qlik LOAD/RESIDENT, the SQL SELECT pass-through exception, and the five most common adjacent failure modes (NoConcatenate, Count() argument requirements, QUALIFY with prefixed fields, DROP TABLE discipline, NullAsValue scope)
- `qvd-operations.md` -- STORE syntax, optimized vs standard read modes, map-building, binary load
- `incremental-load-patterns.md` -- Complete incremental load patterns with working code
- `null-handling-patterns.md` -- vCleanNull, NullAsValue, null guard patterns
- `diagnostic-patterns.md` -- TRACE templates, row count logging, validation queries
- `script-templates/master-calendar.qvs` -- Production-ready master calendar
- `script-templates/error-handling.qvs` -- Error handling and logging framework
- `script-templates/clean-null-function.qvs` -- Null-cleaning variable functions
- `script-templates/dual-timestamp-incremental.qvs` -- SCD Type 2 incremental load
