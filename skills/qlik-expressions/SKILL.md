---
name: qlik-expressions
description: "Set analysis syntax and patterns ({1}, {$}, element-set arithmetic, P()/E(), $(=...) modifiers), aggregation functions, TOTAL qualifier usage, Aggr() patterns, conditional expressions, null handling in expressions, dollar-sign expansion timing, expression performance optimization, calculation conditions, and common Qlik Sense expression anti-patterns. Load when writing, reviewing, or debugging Qlik expressions — master measures, master dimensions, calculated dimensions, KPI formulas, set-analysis snippets, year-over-year and rolling-window calculations, or any expression that misbehaves under selection."
user-invocable: false
---

# Qlik Sense Expressions

Expressions evaluate in the USER's selection context, not in a script context. A chart object displays data based on what the user has selected in filter panes, listboxes, and other selection controls. Set analysis is the mechanism for overriding that selection context programmatically. Expression bugs almost always stem from misunderstanding selection scope. Set analysis is where the confusion begins.

This skill covers aggregation functions, set analysis syntax and patterns, the TOTAL qualifier, the Aggr() function, conditional expressions, null handling, dollar-sign expansion, calculation conditions, expression performance, and anti-patterns.

## 1. Aggregation Functions and Null Behavior

All Qlik aggregation functions skip NULL values by default. This is correct behavior but the consequences are easy to miss.

**Core aggregation functions:**
- `Sum(Field)` — Sums non-NULL values. `Sum([1, NULL, 3])` = 4. If all values are NULL, returns NULL (not 0).
- `Count(Field)` — Counts non-NULL values (not rows). `Count([1, NULL, 3])` = 2. `Count(*)` is not valid in expressions.
- `Count(DISTINCT Field)` — Counts unique non-NULL values. Use when duplicates exist and you only want unique rows counted.
- `Avg(Field)` — Average of non-NULL values: `Avg([1, NULL, 3])` = (1+3)/2 = 2.
- `Min(Field)`, `Max(Field)` — Minimum and maximum non-NULL values.
- `Only(Field)` — Returns the value if exactly one unique non-NULL value exists, NULL otherwise. Critical for lookup aggregations: `Only([Customer.Name])` avoids accidentally aggregating on fields with one value per dimension.
- `NullCount(Field)` — Counts NULL values specifically. Useful for data quality checks.
- `Concat(Field, Delimiter)` — Concatenates non-NULL values with a delimiter. `Concat([Product.Name], ', ')` produces comma-separated product names.

**The NULL aggregation trap:** `Sum()` of all NULLs returns NULL, not 0. If you need 0 instead, wrap with `Alt()` or `RangeSum()` (both operate on numeric values):
```
Alt(Sum([Amount]), 0)
RangeSum(Sum([Amount]), 0)
```
Note: `Alt()` returns the first parameter with a valid NUMERIC representation. Do not use it to coalesce text-valued NULLs — for that, use `Coalesce()` (see Section 9).

## 2. Set Analysis Syntax

Set analysis is the core expression mechanism in Qlik. It overrides the current selection context for specific fields or entire tables.

**Basic syntax:** `Sum({<SetModifier>} Field)`

The curly braces `{}` are required. Everything inside is the set modifier.

**Set identifier (optional, default `$`):**
- `$` — Current selection in the default state (default if omitted)
- `1` — All records in the app, ignoring all selections
- `$_1` — Previous selection in the default state (back button; one step back in selection history). `$_2` is two steps back, and so on. (Source: help.qlik.com — Set analysis identifiers)
- `$1` — Next (forward) selection in the default state (forward button; one step forward in selection history). `$2` is two steps forward, and so on. (Source: help.qlik.com — Set analysis identifiers)
<!-- Cross-reference: see references/set-analysis.md Section 1 "Set Identifier" for the canonical definition. Fix: SPEC-04-01 / SPEC-10-01. -->
- `BookmarkName` (or bookmark ID) — Selections saved in a named bookmark
- `StateName` — Selections in a named alternate state. Referenced by state name, no `$` prefix: `Sum({MyState} [Amount])`. Bookmarks scoped to a state use `StateName::BookmarkName`.

**Set operator (optional, default intersection):**
- `*` — Intersection: include only values that exist in BOTH sets
- `+` — Union: include values from EITHER set
- `-` — Exclusion: remove values from the base set
- `/` — Symmetric difference: include values in one set but not both

**Set modifier:** `<FieldName={values}>`
- Overrides the selection for that field
- Can apply to one or more fields: `<Year={2024}, Region={'East','West'}>`
- Multiple field modifiers are combined with intersection (AND logic)
- Clear a selection with no values: `<Field=>` (empty braces)

**Element set definitions:**
- Explicit values: `{1, 2, 3}` or `{'East', 'West'}`
- Wildcard (all non-null): `{*}` — matches any value EXCEPT null. Use `<Field={*}>` to exclude null values from the aggregation for that field. This is NOT the same as `<Field=>` (which clears/ignores selections on that field).
- Search strings (computed membership): inside a field modifier, e.g., `<Customer={"=Sum(Amount)>1000"}>` — for each Customer, evaluate `Sum(Amount)>1000`; include Customer values where it returns true. Searches are always scoped to a named field and enclosed in double quotes, square brackets, or grave accents.
- Variable references: `{$(vMyVariable)}`
- Functions: `{P(Region)}` (possible values), `{E(Region)}` (excluded values)
- Comparison operators: `Year={">2020"}` or `Month={">=1<=6"}`

**Critical distinction — `{*}` vs `<Field=>` vs omitting the field:**
- `<Field={*}>` — Restrict to non-null values of Field. Actively excludes null. Use when you need to filter out records where a field has no data (e.g., `{<[Per Capita Income]={*}>}` to exclude counties without income data).
- `<Field=>` — Ignore any user selections on Field. The field is unconstrained; null values ARE included. Use when you want the measure to be unaffected by user filter selections on that field.
- Omitting Field from set modifier — Field follows whatever the user has currently selected. Default behavior.

**Quoting rules — single vs. double quotes:**
- Single quotes `'East'` → literal, case-sensitive value match
- Double quotes `"East"` → case-insensitive search (matches 'East', 'EAST', 'east')
- Search strings (expressions starting with `=`, wildcards `*`/`?`) require double quotes, brackets, or grave accents

Mismatching this is silent — the expression compiles but matches more or fewer values than intended.

**Examples:**
```
Sum({$} [Amount])                    // Current selection (explicit $, same as omitting)
Sum({1} [Amount])                    // All data, no selection
Sum({<Year={2024}>} [Amount])        // 2024 only, ignoring current year selection
Sum({<Region={'East','West'}>} [Amount])  // East and West regions
Sum({$+1} [Amount])                  // Current + all data (union)
Sum({<Year={2024}, Month={"<=6"}>} [Amount])  // 2024 first half
```

For the full set analysis reference — set operators, element set patterns, cross-selection (`<Field={}>`), dollar-sign expansion inside modifiers, time intelligence (YTD, prior year, rolling 12 done correctly), cross-table patterns, failure modes, and the anti-pattern catalog — see `references/set-analysis.md`.

## 3. TOTAL Qualifier

TOTAL changes the aggregation scope to ignore the chart's dimensions. This is DIFFERENT from set analysis, which changes selection scope.

**What TOTAL does:** `Sum(TOTAL Amount)` sums across ALL dimension combinations in the data, regardless of what dimensions the chart displays.

**TOTAL with field list:** `Sum(TOTAL <Region> Amount)` ignores all dimensions EXCEPT Region. This creates a "percentage within group" pattern.

**Common TOTAL mistake:** Using TOTAL when set analysis is needed (or vice versa).
- Set analysis `{<...>}` changes what DATA is included (overrides selection)
- TOTAL changes DIMENSION SCOPE (ignores chart dimensions)

They solve different problems. Set analysis answers "exclude deleted orders". TOTAL answers "what percentage of the total is this row?"

**TOTAL for ratios:**
```
Sum(Amount) / Sum(TOTAL Amount)           // Percentage of total
Sum(Amount) / Sum(TOTAL <Region> Amount)  // Percentage within region
```

**TOTAL combined with set analysis:** TOTAL appears AFTER the set analysis closing brace, before the field name:
```
Sum({<Year={2024}>} TOTAL Amount)         // All-dimension total for 2024 only
Sum({<Year={2024}>} TOTAL <Region> Amount) // Region-level total for 2024
```

**Parsing trap:** `Sum({<...>}Total Field)` looks like a field called "Total Field" but Qlik parses `Total` as the TOTAL qualifier keyword. The keyword is case-insensitive. If you actually have a field named "Total Something," you must use square brackets: `Sum({<...>}[Total Something])`. When reviewing expressions, always check whether `Total` before a field name is the TOTAL qualifier or part of the field name.

**Performance note:** TOTAL forces recalculation across all rows. On datasets with millions of rows, this is expensive. Consider pre-calculating in the script (a flag field) when performance matters.

For the complete TOTAL reference — the field-list form `TOTAL <FieldList>`, TOTAL + set analysis combined behavior, the "Total" field-name parsing trap, performance mitigation, and failure modes — see `references/total-qualifier.md`.

## 4. Aggr() Function

Aggr() creates a virtual table (temporary dimension-measure pairs) that Qlik can aggregate over. Essential for calculated dimensions and nested aggregations.

**Basic pattern:** `Aggr(Sum(Sales), Customer)` — Creates a virtual table with one row per unique Customer showing their total Sales.

**Nested aggregation:** `Avg(Aggr(Sum(Sales), Customer))` — Average of per-customer sums. Aggr() is the **only** valid way to nest aggregation scopes. Direct nesting of aggregation functions (e.g., `Avg(Sum(Sales))`) is structurally invalid in Qlik. The engine cannot resolve two aggregation scopes simultaneously. This also applies to hidden nesting via dollar-sign expansion: if a SET variable contains `Sum(...)`, placing `$(vMySum)` inside `Avg()` expands to `Avg(Sum(...))` at render time, which is equally invalid. Always use Aggr() as the intermediate step when an outer aggregation must operate on per-dimension aggregated values.

**Multiple dimensions:** `Aggr(Sum(Sales), Year, Month)` — Virtual table with Year-Month combinations. Useful for time series buckets.

**Aggr with NODISTINCT:** By default, Aggr produces distinct dimension combinations. `Aggr(Sum(Sales), Customer, NODISTINCT)` preserves duplicate rows if they exist (rarely needed).

**Limitations and performance warnings:**
- Aggr's dimension must be an actual field in the data model. Calculated dimensions inside Aggr (e.g., `Aggr(..., Year & Month)`) don't work as expected.
- Aggr creates a virtual table in memory. Nested Aggr (Aggr inside Aggr) compounds memory usage. Use sparingly on large datasets.
- If performance is critical, pre-calculate in the script instead.

For the complete Aggr() reference — virtual-table model, DISTINCT/NODISTINCT, the inner-set vs outer-set distinction, the dimension-vs-measure rule, the calculated-dimension restriction with workarounds, and failure modes — see `references/aggregation-patterns.md`. For Aggr cardinality bands and the Low/Medium/High calculation-weight labeling, see `qlik-performance` § 4.A and § 4.D.

## 5. Conditional Expressions

**IF(condition, then, else)** — Standard conditional. If condition is NULL, evaluates to ELSE branch (not an error).
```
IF(Region='East', Sum([Amount]), 0)
IF(IsNull(field), 'Unknown', field)
```

**Pick(n, val1, val2, ...)** — Index-based selection. Returns value at position n. Useful with Match() for multi-branch logic:
```
Pick(Match(Status, 'Pending', 'Approved', 'Rejected'), 'Not Started', 'In Progress', 'Complete')
```

**Match() / WildMatch() / MixMatch()** — Pattern matching returning position (1-based).
- `Match(field, 'A', 'B')` returns 1 if field='A', 2 if field='B', 0 if no match
- `WildMatch(field, 'prefix*', 'other*')` supports wildcards
- `MixMatch(field, 'A', 'B')` is case-insensitive

**Class(value, min1, min2, ...)** — Range bucketing. `Class(Age, 0, 18, 25, 65)` produces ranges [0-18), [18-25), [25-65), [65+).

**Anti-pattern: deeply nested IF:** Hard to read and error-prone. Prefer Pick(Match(...)) for multi-branch logic:
```
// WRONG - unreadable nesting
IF(Status='A', IF(Region='East', 'EA', 'WA'), IF(Status='B', 'OB', 'OTHER'))

// RIGHT - clear precedence with Pick/Match
Pick(Match(Status, 'A', 'B'),
    Pick(Match(Region, 'East', 'West'), 'EA', 'WA'),
    'OB',
    'OTHER')
```

## 6. Dollar-Sign Expansion in Expressions

Dollar-sign expansion substitutes variable text into expressions at evaluation time. The critical rule: **commas inside $() are parameter delimiters, not expression commas.**

**Variable references:** `$(vMyVariable)` expands the variable's text content.

**Parameterized expressions:** `$(vCalc(arg1, ...))` where vCalc is a SET variable function. Inside the variable body, `$1`, `$2`, ... are textual placeholders that the engine substitutes BEFORE the surrounding expression parses. Example — a year-over-year delta where the caller supplies the field and an offset:
```
SET vYearOverYear = (Sum({<Year={$(=Max(Year))}>} $1) - Sum({<Year={$(=Max(Year)-$2)}>} $1));
$(vYearOverYear([Amount], 1))
// Expands to: (Sum({<Year={$(=Max(Year))}>} [Amount]) - Sum({<Year={$(=Max(Year)-1)}>} [Amount]))
```
Per help.qlik.com Cloud — Dollar-sign expansion using parameters, the `$1`, `$2` placeholders are text substitution: the caller's argument is dropped into the variable body verbatim before parsing continues.

**The comma limitation (critical):** Expressions with commas cannot be passed as arguments to variable functions. Commas are interpreted as parameter delimiters:
```
// WRONG - ApplyMap's commas break parameter parsing:
$(vCleanNull(ApplyMap('MyMap', field, 'default')))
// The engine sees: $1=ApplyMap('MyMap', $2=field, $3='default')

// RIGHT - write inline when expression contains commas:
IF(IsNull(ApplyMap('MyMap', field, 'default')), Null(), ApplyMap('MyMap', field, 'default'))
```

Common violations: ApplyMap (has commas), PurgeChar (has comma), IF (has commas), Concat (has comma).

When a variable function cannot wrap an expression due to commas, write the equivalent logic inline and add a comment.

**Dynamic set analysis:** `Sum({<Year={$(vCurrentYear)}>} Sales)` — Variable expands before set analysis evaluates.

**Evaluation timing:**
- `$(variable)` substitutes the variable's text content at parse time
- `$(=expression)` forces immediate evaluation and substitutes the result at parse time
- This matters for dynamic labels: `=$(=Sum(Amount))` shows the evaluated sum in a text box

Reference `references/set-analysis.md` § Dollar-Sign Expansion Inside Set Modifiers for dynamic set modifiers, the comma trap, and indirect references like `Year={$(=Max(Year))}`.

For SET vs LET decision criteria, the comma trap with workarounds, trailing-semicolon discipline, and the conventional structure of an `expression-variables.qvs` file, see `references/variable-rules.md`.

## 7. Calculation Conditions

Calculation conditions prevent expensive calculations when the result would be meaningless (e.g., showing all-time data when the user expects a filtered view).

**Object-level calculation condition:** An expression that must evaluate to TRUE (-1) for the object to calculate. If FALSE, displays a message.

**Common patterns:**
```
Count(DISTINCT Year) = 1                    // Requires single year selected
GetSelectedCount(Region) > 0                // Requires region selection
Count(DISTINCT [Customer.Key]) < 10000      // Prevents slow cross-product
NoOfRows('$') > 100                         // Only show if enough data rows
```

**Sheet-level calculation conditions:** Available in Qlik Sense. Use for sheets that would timeout without selections.

**The trap:** A calculation condition that's too restrictive frustrates users ("why can't I see this data?"). Too permissive causes slow rendering. Balance is project-specific. Consult with users before deploying restrictive conditions.

## 8. Expression Performance Optimization

**Set analysis beats flag multiplication for large datasets.** Per Henric Cronström's tests on a 100M-row fact table (Qlik Design Blog), set analysis benefits from index optimization and a smaller post-filter aggregation footprint:
```
// Fast on large datasets - indexed selection, smaller aggregation set
Sum({<IsReturned={0}>} Amount)

// Roughly equivalent for small datasets, slower for large
Sum([IsReturned] * [Amount])
```
For small fact tables (a few million rows), the difference is negligible — flag multiplication's per-row overhead is constant but cheap. Reach for flag multiplication only when (a) the flag lives on the fact table itself and (b) the dataset is small enough that set analysis's fixed setup cost is wasted.

**Pre-calculate in script what doesn't need to be dynamic:**
- Age groups, fiscal periods, seasonal labels — calculate at load time
- Complex business rules applied to every transaction — use derived fields

**Use variables for repeated sub-expressions:**
Variables are calculated once and referenced many times. Better than repeating the same expression.

**Minimize Aggr() usage on large datasets:**
Aggr creates virtual tables in memory. Each level of nesting multiplies memory use. Pre-aggregate in the script if the result doesn't need to be dynamic.

**TOTAL is expensive:**
TOTAL forces row-by-row recalculation. Pre-calculate totals as a script field when used repeatedly.

**Set analysis is generally faster than flag multiplication for large datasets:**
For large fact tables, prefer `Sum({<Flag={1}>} Amount)` over `Sum([Flag] * [Amount])`. Set analysis can use index optimization and shrinks the aggregation footprint; multiplication forces a per-row scan. The two are roughly equivalent on small datasets (Henric Cronström, "Performance of Conditional Aggregations," Qlik Design Blog).

**Calculation conditions prevent unnecessary heavy calculations:**
If a sheet condition fails, all calculations on that sheet skip. This saves processing time.

## 9. Null Handling in Expressions

This is the canonical home for expression-layer null handling. For script-layer null handling (`vCleanNull`, `NullAsValue`, date sentinel guards), see `qlik-load-script/references/null-handling.md`.

### Baseline behaviors

**Aggregation functions skip NULLs.** `Sum([1, NULL, 3])` = 4, not NULL. `Avg([1, NULL, 3])` = 2 (computed from two non-NULL values, not three). `Min` / `Max` ignore NULLs.

**`Sum` of all NULLs returns NULL, not 0.** Empty selections or fully-NULL fields produce NULL. Wrap with `Alt()` or `RangeSum()` when 0 is the semantically correct display value.

**`Count(field)` counts non-NULL values, not rows.** `Count([1, NULL, 3])` = 2. For total row counts, use `NoOfRows('TableName')`. `Count(*)` is not valid in Qlik chart expressions — see `qlik-load-script/references/sql-constructs.md` Section 2.2.

**`Count(DISTINCT field)` counts unique non-NULL values.** NULLs are excluded from the distinct count.

**`NullCount(field)` returns the count of NULL values.** Use for null-rate diagnostics in charts and scripts. Reference: help.qlik.com — NullCount script and chart functions.

**Division by zero returns NULL.** `1/0` = NULL, `5/0` = NULL. Qlik does not raise an error; the NULL propagates silently. This is safe but can hide logic errors in downstream aggregations.

**Comparison with NULL returns False (not NULL).** Per help.qlik.com Cloud null-value-handling: "A = NULL returns False (0)". This is true for `=`, `<>`, `<`, `>`, `<=`, `>=`. The only correct NULL test is `IsNull(field)`.

**Arithmetic with NULL returns NULL.** Per help.qlik.com: "If NULL is encountered on any side of these operators NULL is returned." Applies to `+`, `-`, `*`, `/`, `%`. So `5 + NULL = NULL` and `NULL * 0 = NULL`.

### `Alt()` for numeric coalescing

Per help.qlik.com — Alt function: "the alt function returns the first of the parameters that has a valid number representation. If no such match is found, the last parameter will be returned."

Use `Alt()` only for **numeric** fallback:

```
Alt(Sum([Amount]), 0)        // Returns 0 when Sum produces NULL
Alt([Order.Year], Today())   // Returns Today() when Order.Year has no numeric representation
```

**Common mistake:** `Alt([Customer.Name], 'Unknown')` always returns `'Unknown'` because a name like `"Acme Corp"` has no valid numeric representation. Reach for `Coalesce()` whenever the values are text.

### `Coalesce()` for general (text or numeric) null coalescing

Per the docs: "the coalesce function returns the first of the parameters that has a valid non-NULL representation." Use `Coalesce()` when fallback values are text or when a non-numeric value needs a default:

```
Coalesce([Customer.Name], 'Unknown')
Coalesce([Product.Description], [Product.Name], [Product.Code], 'No description')
```

### `RangeSum()` for null-safe addition

Per help.qlik.com — RangeSum function: "The RangeSum function treats all non-numeric values as 0," and the example `RangeSum(null())` returns 0. Use when aggregating optional or sparse columns where NULL should contribute zero:

```
// Quarterly revenue where any quarter may be NULL.
// Plain Sum(Q1+Q2+Q3+Q4) returns NULL if any quarter is NULL.
RangeSum(Sum([Q1.Amount]), Sum([Q2.Amount]), Sum([Q3.Amount]), Sum([Q4.Amount]))

// Equivalent to Alt(Sum(...), 0) for a single expression, but more efficient
// for multi-argument null-safe addition than nested Alt() calls.
RangeSum(Sum([Amount]), 0)
```

### `Null()` constructor

Explicitly returns NULL. Useful for the NULL branch of conditional expressions where downstream logic should ignore the row:

```
IF(IsNull(field), Null(), Sum(field))
IF([Order.Status] = 'Cancelled', Null(), [Order.Amount])
```

### Division-by-zero and null guard

Division by both zero and NULL produces NULL by Qlik default (silent NULL propagation for `/0` and arithmetic NULL propagation for `n / NULL`). Wrapping the division in an explicit guard documents intent and makes the NULL semantic visible to readers:

```
IF(IsNull(vDenominator) OR vDenominator = 0, Null(), vNumerator / vDenominator)
```

- If `vDenominator` is NULL: `IsNull` returns true, expression returns `Null()`.
- If `vDenominator` is 0: `IsNull` returns false, `= 0` returns true, expression returns `Null()`.
- If `vDenominator` is non-zero: division proceeds normally.

**On clause ordering.** Both `IF(IsNull(d) OR d = 0, ...)` and `IF(d = 0 OR IsNull(d), ...)` produce the same result, because Qlik's `=` returns False (not NULL) when one side is NULL, and `IF` treats both False and NULL conditions as "go to else." The IsNull-first ordering is the convention because it documents the NULL intent before the zero intent — useful when the next reader is checking what cases the guard covers, not because the reversed order is incorrect.

**Without the guard.** The unguarded `vNumerator / vDenominator` returns NULL for both the zero and NULL cases anyway (Qlik does not throw on division by zero). The guard adds value when (a) the calling context needs an explicit NULL branch (e.g., for a `Coalesce` fallback), or (b) the expression is large and a reader might assume `/0` would error.

### Documentation requirement

When producing a measure catalog, every measure entry must document its null handling. Examples:

- `Sum(...) returns NULL for empty selections. Wrap with Alt(Sum(...), 0) in KPI displays where 0 is the desired zero-data value.`
- `Count(...) excludes NULL values. Returns 0 for empty selections (no rows to count).`
- `IF(IsNull(...), 'No Data', ...) — returns 'No Data' string when field is NULL.`
- `IF(vDenominator = 0 OR IsNull(vDenominator), Null(), ...) — returns NULL on division by zero or NULL denominator.`

The reader of the catalog should never have to guess what an aggregation does on empty selections, NULL fields, or division-by-zero conditions.

### Failure modes

- **Silent NULL from intermediate-layer field names.** `Sum([Account.Region])` produces NULL after the DataModel layer renamed `Account` to `Customer` (the field no longer exists). Symptom: a measure that was working in a prototype now returns NULL after a field rename. Fix: always reference the final UI field name; see `qlik-naming-conventions` for cross-layer naming.
- **Comparison with NULL is False, not NULL.** `IF(field = 'value', ...)` when `field` is NULL returns the `else` branch (because `= NULL` is False, and `IF` treats False as "go to else"). Use `IF(IsNull(field), ...)` to branch on NULL specifically.
- **Arithmetic NULL propagation in chained expressions.** `(A + B) * C` returns NULL if any of A, B, C is NULL. Wrap with `RangeSum()` for the addition step, or with `IsNull` guards for the chain.
- **`Alt()` on text values.** `Alt([Customer.Name], 'Unknown')` returns `'Unknown'` even when `Customer.Name` is a perfectly valid non-NULL name like `"Acme Corp"`, because `"Acme Corp"` has no valid numeric representation. Use `Coalesce()` for text.

## 10. Common Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|---|---|---|
| Operator without left-side set identifier | `{*<Year={2024}>}` — the `*` operator needs a set on its left. Parse error or unexpected behavior. | Add an explicit identifier: `{$*<Year={2024}>}` (intersect current selection with Year=2024). Same applies to `+`, `-`, `/`. |
| Using TOTAL when set analysis needed | TOTAL changes dimension scope, not selection. Wrong tool for the job. | Use set analysis `{<...>}` to override selections. Use TOTAL to change aggregation scope. |
| Deeply nested IF | Unreadable, error-prone, hard to maintain | Use Pick(Match(...)) for multi-branch logic |
| `Sum(field1 * field2)` vs. `Sum(field1) * Sum(field2)` | These produce different results. First aggregates products, second multiplies aggregates. Only the second is "revenue per unit × units = total." | Choose deliberately based on business logic. Document which is intended. |
| Forgetting Alt() or RangeSum() | NULL + something = NULL. Unexpected NULL results. | Use Alt() or RangeSum() for null-safe arithmetic. |
| Hardcoded year values in set analysis | `{<Year={2024}>}` is brittle. If you need current year dynamic, use variable. | Use variables: `{<Year={$(vCurrentYear)}>}` |
| Aggr() with calculated dimensions | Aggr expects field names, not expressions. Calculated dimensions don't work. | Use only actual fields in Aggr dimension list. Pre-calculate in script if needed. |
| Missing DISTINCT in Count | Count([field]) counts non-NULL rows. If duplicates exist and you want unique, you miss DISTINCT. | Use `Count(DISTINCT field)` when uniqueness matters. |
| Wrong element set syntax in set analysis | Missing quotes on string values: `{<Region={East}>}` (East is a variable, not literal). Bracket confusion. | String literals need quotes: `{<Region={'East'}>}`. Use `{}` for implicit sets, `{}` shorthand for explicit. |
| Using SET variable without understanding comma limitation | Passing expressions with commas to variable functions breaks. | Never pass expressions with commas to variable functions. Write inline instead. |

For more anti-pattern details with examples, see `references/set-analysis.md` § Anti-Pattern Catalog.

## Supporting Files

- `references/set-analysis.md` — complete set analysis syntax (identifiers, operators, field modifiers, element sets, quoting), exclusion patterns (`-=` and `{1-<...>}`), dollar-sign expansion inside set modifiers (comma trap, no-nesting rule), time intelligence (YTD, prior year, rolling 12 — date-based and sequential-month-key forms), cross-table and alternate-state patterns, advanced patterns (cross-selection, set + TOTAL, set + Aggr, Top N, conditional modifiers), failure modes (silent NULL from intermediate-layer renames, Dual-field type sensitivity), and the anti-pattern catalog.
- `references/total-qualifier.md` — TOTAL semantics, the field-list form, TOTAL + set analysis combined behavior, the percentage-of-total pattern, the "Total" field-name parsing trap, performance mitigation, failure modes, and catalog documentation conventions.
- `references/aggregation-patterns.md` — `Aggr()` virtual-table model, DISTINCT vs NODISTINCT, multi-dimension grouping, the inner-set vs outer-set distinction, the calculated-dimension restriction, the dimension-vs-measure rule, hidden nesting via dollar-sign expansion, failure modes, and catalog conventions.
- `references/variable-rules.md` — SET vs LET decision criteria (tier-1 `Let` semantics, the dynamic-UI rule, the SET-doesn't-evaluate-function-calls trap), dollar-sign expansion comma rules and workarounds, trailing-semicolon discipline, `expression-variables.qvs` organization with section conventions, and catalog conventions.
