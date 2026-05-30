# Set Analysis Reference

Canonical home for set analysis: syntax structure, element set definitions, set operators, cross-selection, dollar-sign expansion inside modifiers, time intelligence patterns, failure modes, and anti-patterns. Companion to `qlik-expressions/SKILL.md` Section 2 (basic syntax).

## 1. Complete Syntax Reference

**Full set analysis grammar:**

```
{[SetIdentifier] [SetOperator] <FieldModifier1={ElementSet1}[, FieldModifier2={ElementSet2}, ...]>}
```

Every component is optional. The default set is the current selection (`$`), so `Sum(Amount)` is equivalent to `Sum({$} Amount)`.

### Set Identifier
- `$` — Current selection in the default state (default if omitted)
- `1` — All records in the app, ignoring all selections
- `$1` — Previous selection in the default state (back-button history). `$2` is two back, and so on.
- `$_1` — Next (forward) selection in the default state. `$_2` is two forward.
- `BookmarkName` (or bookmark ID) — Selections from a saved bookmark
- `StateName` — Selections in a named alternate state (referenced by state name, no `$` prefix). Use `StateName::BookmarkName` for a bookmark scoped to a state.
- Omitted — Defaults to `$` (current selection)

### Set Operator (set-level)
Combines the set identifier with another set. The operator appears between two sets, not inside a field modifier.

- `*` (intersection) — Include values that exist in BOTH sets (AND).
- `+` (union) — Include values that exist in EITHER set (OR).
- `-` (exclusion) — Start with the left set and remove values that are in the right set.
- `/` (symmetric difference) — Include values in one set but not both.

Operator is applied AFTER the set identifier. Default (omitted operator) is intersection of the identifier with the field modifiers.

Examples (set-level):
```
{$ * <Year={2024}>}            // Current selection AND Year=2024
{$ + 1<Year={2024}>}            // Current selection PLUS all-data restricted to 2024
{1 - <OrderType={'Returns'}>}   // All data MINUS records where OrderType=Returns
```

### Field Modifiers
`<FieldName={ElementSet}>`

Each modifier overrides the selection for that field. Multiple field modifiers separated by commas apply with intersection (AND) by default:

```
<Year={2024}, Region={'East'}>          // AND: Year=2024 AND Region=East
```

### Implicit (field-level) Operators
Operators attached to the field name (with `=`) modify the existing selection on that field instead of replacing it.

- `Field+={values}` — Add values to the current selection on Field.
- `Field-={values}` — Remove values from the current selection on Field (exclusion).
- `Field*={values}` — Restrict the current selection on Field to also satisfy this requirement.
- `Field/={values}` — Keep values in one set but not both.

Examples:
```
Sum({<Country+={'France'}>} [Sales])    // Current selection PLUS France on Country
Sum({<Country-={'Canada'}>} [Sales])    // Current selection MINUS Canada on Country
Sum({<Country*={'France', 'Germany'}>} [Sales])   // Intersect current Country selection with {France, Germany}
```

Implicit operators apply only to the named field. Other fields keep their current selections.

**Negation trap (`-=` is exclusion, not negation).** Empty exclusion includes everything:

```
{<Status-={}>}    // Excludes nothing — equivalent to no modifier on Status
{<Status-={'Cancelled','Returned'}>}    // Excludes only Cancelled and Returned
```

This trips up authors who reach for `-=` expecting "NOT" semantics. Reach for `E()` or use `={"=NOT condition"}` searches when negation is what you need.

### Element Sets
What values to include in the field modifier.

- **Explicit list:** `{'East', 'West'}` or `{1, 2, 3}`. String values require quotes.
- **Wildcard (all non-null):** `{*}` — matches any value EXCEPT NULL.
- **Search string:** `<Customer={"=Sum(Amount)>1000"}>` — expression is evaluated for each value of Customer; values where the expression is true are included. Searches must be enclosed in double quotes, square brackets, or grave accents.
- **Variable expansion:** `{$(vMyVariable)}` — variable is expanded into the element set.
- **Functions:** `{P(Region)}` (possible values in current selection), `{E(Region)}` (excluded values from current selection).
- **Comparison operators:** `Year={">2020"}` or `Month={">=1<=6"}` — string comparison for ranges (see Section 3).
- **Empty set:** `<Field={}>` — clears the selection on that field, making it contribute nothing to the aggregation.

### Critical Distinction — `{*}` vs `<Field={}>` vs `<Field=>` vs omitting

- `<Field={*}>` — Restrict to non-NULL values of Field. Actively excludes NULL. Use when you need to filter out records where a field has no data (e.g., `{<[Per Capita Income]={*}>}` to exclude counties without income data).
- `<Field={}>` — Empty element set. The field is constrained to "no values," which means the field carries no constraint into the aggregation. Equivalent to "ignore selections on Field." NULL values ARE included.
- `<Field=>` — Same as `<Field={}>`. Both forms clear the selection. Use whichever is local convention.
- Omitting Field from the set modifier — Field follows whatever the user has currently selected. Default behavior.

The `<>` form (empty braces with no modifiers) is `<>` — ignore all selections. Easy to write unintentionally; produces "all data ignoring all selections," equivalent to `{1}`.

### Quoting Rules (Critical)

Single and double quotes have different semantics inside element sets:

- **Single quotes** `'East'` → literal, case-sensitive value match.
- **Double quotes** `"East"` → case-insensitive search.
- **Square brackets** `[East]` and **grave accents** `` `East` `` are equivalent to double quotes (case-insensitive search).
- **Search strings** (expressions starting with `=`, or text containing wildcards `*` / `?`) MUST use double quotes, brackets, or grave accents.

Picking the wrong quote silently changes the result set. Use single quotes when you want an exact literal match; reach for double quotes only for case-insensitive matching or true search.

### Element Set Type Sensitivity (Dual fields)

Element sets distinguish between numeric and text matches based on quoting style. For Dual fields (fields where the same Qlik value carries both a number and a text representation, e.g., `Dual('Yes', 1)`), this matters:

- `{<[Year]={'2024'}>}` — string comparison. Matches the text "2024".
- `{<[Year]={2024}>}` — numeric comparison. Matches the number 2024.

These are NOT equivalent if Year contains both string and numeric encodings (e.g., a Dual field where some records hold `Dual('FY2024', 2024)`). The unquoted form matches the numeric encoding; the quoted form matches the text encoding. A Dual field record with text "FY2024" and numeric 2024 will match `{2024}` but not `{'2024'}`.

When in doubt with Dual fields, examine the field with `Text(field)` and `Num(field)` to confirm which representation the data uses.

---

## 2. Set Operator Patterns with Business Scenarios

### Intersection (`*`)
Combine sets with AND logic. Include only values that exist in BOTH sets.

**Scenario:** Sales for regions that are BOTH in this year's plan AND had activity last year.
```
Sum({$*<Year={$(vCurrentYear)}>} [Order.Amount])
```
- Start with current selections (`$`)
- Intersect with: Year = current year
- Result: Respects all current selections, but forces year to current

**More complex:** Regions that have BOTH completed orders AND planned budget.
```
Sum({<OrderStatus={'Completed'}>*<BudgetStatus={'Approved'}>} [Amount])
```

### Union (`+`)
Combine sets with OR logic.

**Scenario:** Revenue from active customers OR customers with recent activity.
```
Sum({<CustomerStatus={'Active'}>+<LastPurchaseDate={">2024-01-01"}>} [Revenue])
```

**Time intelligence use:** Current month OR prior month.
```
Sum({<Month={$(vCurrentMonth)}>+<Month={$(vPriorMonth)}>} [Amount])
```

### Exclusion (`-`)
Remove values from the base set. Two equivalent shapes:

**Set-level exclusion** (using the `-` operator between sets):
```
Sum({1-<OrderType={'Returns'}>} [Amount])
// {1} = all data, then subtract records where OrderType = Returns
// Result: all data EXCEPT returns
```

**Field-level exclusion** (using the implicit `-=` operator on the field):
```
Sum({<OrderType-={'Returns'}>} [Amount])
// Start with current selection, remove 'Returns' from OrderType selection
// Result: current selection MINUS Returns
```

The two differ on whether other selections are respected:
- Set-level `{1-<...>}` ignores ALL current selections (because `{1}` is all data).
- Field-level `{<F-={...}>}` keeps all other selections; only Field's selection is reduced.

For typical "exclude cancelled and returned orders," field-level is usually the right choice:
```
Sum({<[Order.Status]-={'Cancelled','Returned'}>} [Order.Amount])
```

### Symmetric Difference (`/`)
Include values in one set but NOT both. Rarely used.

```
Count({<IsRecent={'Yes'}>/<IsHighValue={'Yes'}>} [Customer.Key])
// Customers who are recent OR high-value, but not both
```

---

## 3. Element Set Patterns

### Explicit Values
Strings require single quotes for literal matches.

```
Sum({<Region={'East', 'West'}>} [Amount])
Sum({<Month={1, 2, 3}>} [Amount])
Sum({<Status={'Active', 'Pending'}>} [Amount])
```

Numbers can be quoted or unquoted: `{1, 2}` or `{'1', '2'}` (see Type Sensitivity note in Section 1 for the Dual-field caveat).

### Wildcard Matching
The `*` (Qlik wildcard, not the set operator) matches any character sequence inside a value.

```
Sum({<Product={'Acme*'}>} [Amount])      // Products starting with "Acme"
Sum({<Email={"*@example.com"}>} [Amount]) // Emails ending @example.com (double quotes for search)
```

Wildcards inside element sets require double-quote, bracket, or grave-accent quoting (search-string rules).

### Search Strings (Computed Membership)
Expression evaluated for each value of the scoped field. Only values where the expression is true are included.

```
Sum({<Product={"=Sum(Amount)>1000"}>} [Amount])
```
- For each Product, evaluate `Sum(Amount) > 1000`.
- Include only Products where the sum exceeds 1000.
- The outer `Sum([Amount])` then aggregates over those Products.

**Data quality example:** Sum of revenue from products with no null quantities.
```
Sum({<[Product.Key]={"=NullCount([OrderLine.Qty])=0"}>} [OrderLine.Amount])
```

**Independent-context search:** Use a nested `{1}` set inside the search to ignore current selections when evaluating the predicate.
```
Sum({<[Product.Key]={"=Sum({1} [OrderLine.Amount])>10000"}>} [OrderLine.Amount])
```

### Variable Expansion
Variable is substituted into the element set.

```
SET vSelectedRegions = 'East', 'West';
Sum({<Region={$(vSelectedRegions)}>} [Amount])
// Expands to: Sum({<Region={'East', 'West'}>} [Amount])
```

See Section 4 for dollar-sign expansion mechanics and the comma trap.

### P() and E() Functions
`P(Field)` returns possible values (values that exist in the current selection). `E(Field)` returns excluded values (values NOT in the current selection).

```
Sum({<Region={E(Region)}>} [Amount])
// Sales from regions the user has NOT selected
```

`P(Region)` is usually redundant (same as current selection); `E(Region)` is the more practical use.

### Comparison Operators in Element Sets
String comparison for ranges and pattern matching.

```
Year={">2020"}                // Years greater than "2020" (string comparison)
Month={">=1<=6"}              // Months between "1" and "6" (string comparison)
OrderDate={">2024-01-01"}     // Dates after "2024-01-01" (string-comparable dates)
```

**Important:** These are STRING comparisons, not numeric. `Year={">2020"}` works for 4-digit years because "2021" > "2020" as strings. For non-zero-padded months, `Month={">=01<=06"}` is safer than `Month={">=1<=6"}` to handle both "01" and "1" representations.

Range syntax `{">=X<=Y"}` requires the operators to be inside a single quoted string per the element set. Splitting them as `{">=X", "<=Y"}` does NOT create a range — it creates a two-value enumeration of strings ">=X" and "<=Y", which match nothing.

---

## 4. Dollar-Sign Expansion Inside Set Modifiers

Set modifiers commonly embed variables for dynamic values. The expansion happens at parse time, before set analysis is evaluated. Two patterns matter:

**Plain variable expansion:** `$(variable)` substitutes the variable's text content.
```
SET vCurrentYear = Num(Today(), 'YYYY');
Sum({<Year={$(vCurrentYear)}>} [Amount])
// At render: Sum({<Year={2026}>} [Amount])
```

**Indirect (computed) expansion:** `$(=expression)` forces expression evaluation, then substitutes the result.
```
Sum({<Year={$(=Max(Year))}>} [Amount])
// $(=Max(Year)) evaluates to the highest year in data
// At render: Sum({<Year={2026}>} [Amount])
```

The `$(=...)` form is essential when the bound value must come from data (e.g., the max year in the loaded set) rather than from a load-time variable.

**Multiple modifiers, multiple variables:**
```
Sum({<Year={$(vCurrentYear)}, Month={$(vCurrentMonth)}>} [Amount])
```
The commas separating field modifiers are safe — they're NOT inside `$()`. The comma trap below applies only to commas INSIDE the `$()` boundary.

### The comma trap (dollar-sign expansion in variables containing commas)

Commas inside `$()` are parameter delimiters for variable functions, not expression commas. This breaks expressions that contain commas (ApplyMap, IF, Concat, PurgeChar) when wrapped in a variable function:

```
// WRONG -- ApplyMap's commas break parameter parsing:
SET vCleanField = ApplyMap('MyMap', $1, 'default');
Sum({<Region={$(vCleanField(Country))}>} [Amount])
// The engine sees: $1=ApplyMap('MyMap', $2=Country, $3='default')
// Misparses, returns NULL or errors.

// RIGHT -- write inline when the inner expression contains commas:
Sum({<Region={"=ApplyMap('MyMap', Country, 'default')"}>} [Amount])

// RIGHT alternative -- pre-resolve in load script:
[Mapped]:
LOAD Country, ApplyMap('MyMap', Country, 'default') AS MappedCountry RESIDENT ...;
Sum({<Region={MappedCountry}>} [Amount])
```

Common violations: `ApplyMap` (commas), `IF` (commas), `PurgeChar` (comma in arg), `Concat` (comma delimiter).

When a variable function cannot wrap an expression due to commas, write the equivalent logic inline and add a comment explaining the workaround.

### No nesting inside `$()` parameters

`{<Field={$($1)}>}` is invalid. The inner `$1` is a parameter reference, not a variable to expand. Pre-expand:

```
SET vFieldValue = $(vOtherVar);
Sum({<Field={$(vFieldValue)}>} [Amount])
```

---

## 5. Time Intelligence Patterns

### Year-to-Date (YTD)
Sum for current year through current month.

```
SET vCurrentYear = Num(Today(), 'YYYY');
SET vCurrentMonth = Num(Today(), 'MM');

Sum({<Year={$(vCurrentYear)}, Month={"<=$(vCurrentMonth)"}>} [Amount])
// Current year, months 1 through current month
```

**Assumption:** Month field is numeric (01..12) or zero-padded text. For mixed representations, normalize Month at load time.

### Prior Year Comparison
Sum for the same period last year.

```
Sum({<Year={$(=Max(Year)-1)}>} [Amount])
// Max year in data minus one — anchors to data, not Today()
```

**Prior year same month:**
```
SET vCurrentYear = Num(Today(), 'YYYY');
SET vCurrentMonth = Num(Today(), 'MM');

Sum({<Year={$(=$(vCurrentYear)-1)}, Month={$(vCurrentMonth)}>} [Amount])
```

### Prior Year YTD
Same months as current YTD, but prior year.

```
SET vPriorYear = $(vCurrentYear)-1;
Sum({<Year={$(vPriorYear)}, Month={"<=$(vCurrentMonth)"}>} [Amount])
```

### Rolling 12 Months (date-based)

The reliable rolling-12 pattern uses a date field and AddMonths(). Avoid YYYYMM-as-integer arithmetic — subtracting 11 from a YYYYMM key produces invalid month codes when crossing year boundaries (e.g., `202605 - 11 = 202594`, not `202506`).

```
SET vRolling12Start = Date(AddMonths(Today(), -11), 'YYYY-MM-DD');
SET vToday = Date(Today(), 'YYYY-MM-DD');

Sum({<[Order.Date]={">=$(vRolling12Start)<=$(vToday)"}>} [Amount])
// Date string comparison works because YYYY-MM-DD sorts lexically as date
```

### Rolling 12 Months (sequential month-number key)

If the data model has a truly sequential month number (e.g., `MonthSeq = Year * 12 + Month`, monotonically increasing across years), the arithmetic version works:

```
Sum({<[Order.MonthSeq]={">=$(=Max([Order.MonthSeq])-11)<=$(=Max([Order.MonthSeq]))"}>} [Amount])
```

Why no intermediate variable: `SET vMyVar = $(=Max(...))` stores the *literal text* `$(=Max(...))` (SET preserves expression text without evaluating it), so a later `$(vMyVar)` re-expands the original `$(=...)`. That nesting compounds inside another `$(=$(vMyVar)-11)` and depends on parse order — fragile and easy to break. Inlining `$(=Max([Order.MonthSeq]))` evaluates once at chart time and avoids nested expansion entirely. If a named variable is preferred for readability, use `SET vCurrentMonthSeq = Max([Order.MonthSeq]);` (no `$(=)` wrapper) and reference it as `$(=$(vCurrentMonthSeq)-11)`.

Note: `MonthSeq` here is `Year*12 + Month`, not YYYYMM. YYYYMM is NOT sequential across year boundaries (December → January jumps 89, not 1) and breaks all minus-N arithmetic.

### Period Comparison (Side-by-Side)
Current period vs. prior period in the same chart (requires two measures).

```
Sum([Amount]) AS [Current Period]
Sum({<Year={$(=Max(Year)-1)}>} [Amount]) AS [Prior Period]
```

---

## 6. Cross-Table Set Analysis Patterns

### Filtering One Fact Table by a Dimension Value Without Affecting Another
Two fact tables (Orders, Returns) associated through Product.

```
Sum({<ProductCategory={'Electronics'}>} [Order.Amount]) AS [Electronics Orders]
Sum({<ProductCategory={'Electronics'}>} [Return.Amount]) AS [Electronics Returns]
```

The set modifier `<ProductCategory={'Electronics'}>` applies to both tables. Product association flows through to both fact tables via the data model.

### Using Alternate States for Comparative Analysis
Alternate states let one app hold multiple independent selection sets. A state is referenced in set analysis by its name, with NO `$` prefix.

```
Sum({$} [Amount]) AS [Current Selections]
Sum({Selection1} [Amount]) AS [Saved Selection 1]
Sum({Selection2} [Amount]) AS [Saved Selection 2]
```

- `$` — Active selections in the default state
- `Selection1` — Independent selections in an alternate state named "Selection1"

Do NOT write `{$Selection1}` — the `$` prefix is reserved for default-state selection history (`$1`, `$2`, `$_1`). Alternate states are referenced by bare name. State names cannot start with `$` or `$_` followed by a digit, and cannot be `$`, `0`, or `1`.

### Set Analysis with Dimensions from Different Tables
Qlik association propagates field selections across related tables.

```
Sum({<[Product.Category]={'Electronics'}>} [Order.Amount])
// Selects products in Electronics category (from Product dimension)
// Filters to orders containing those products (through Order.ProductKey)
// Association is automatic through the data model
```

If the dimension and fact are not directly associated (different keys), a bridge table or explicit script-level resolution is needed.

---

## 7. Advanced Patterns

### Cross-Selection / Scope Override
Override the user's selection on specific fields while leaving others intact.

```
Sum({<Region={}>} [Amount])
// Ignore the user's Region selection; show ALL regions
// Other selections (Year, Customer, etc.) still apply
```

Use case: show a metric for all regions while the user has filtered to one, for "compare to all" patterns.

**Total scope override:**
```
Sum({<>} [Amount])    // Empty braces — ignore ALL selections
Sum({1} [Amount])     // Equivalent: all data, no selections respected
```

Easy to write `{<>}` unintentionally when refactoring; double-check that "ignore everything" is the intended scope.

### Set Analysis Combined with TOTAL
Override selection (set analysis) AND change dimension scope (TOTAL).

```
Sum({<Year={2024}>} [Amount]) / Sum(TOTAL {<Year={2024}>} [Amount])
// Numerator: 2024 amounts for current dimension combination
// Denominator: 2024 amounts across ALL dimension combinations
// Result: Percentage of 2024 total for this row
```

The `TOTAL` applies to the entire aggregation; set analysis filters what data feeds it. See SKILL.md Section 3 for TOTAL semantics.

### Set Analysis with Aggr()
Virtual table aggregation combined with set selection override.

```
Avg(Aggr(Sum({<Year={2024}>} [Amount]), [Customer.Key]))
// Virtual table: Customer → 2024 sum (per customer)
// Then average across customers — "average 2024 sales per customer"
```

Without the set modifier, Aggr would include all years. The set modifier scopes Aggr's inner aggregation. The grouping dimension `[Customer.Key]` is NOT affected by the set filter — only the inner Sum is.

### Top N via Search Strings
Include only the top N values by measure.

```
Sum({<[Product.Key]={"=Rank(Sum([Amount]))<=10"}>} [Amount])
// For each Product, rank its total sales; include top 10
```

This pattern is expensive on large datasets — Rank() inside a search string forces per-value evaluation. Prefer a script-level Top-N flag when the threshold is stable.

### Conditional Set Modifiers via $(=IF(...))
Dynamic modifier value chosen at render time.

```
Sum({<Year={$(=IF(GetSelectedCount(Year)>0, Only(Year), Max(Year)))}>} [Amount])
// If user has selected a single Year, use it; otherwise use max year in data
```

---

## 8. Failure Modes

### Silent NULL from intermediate-layer field names
`Sum({<[Account.Region]={'East'}>} [Amount])` produces NULL after the DataModel layer renamed `Account.Region` to `Customer.Region` (the field no longer exists in the UI layer). Symptom: an expression that was working in a prototype suddenly returns NULL.

Fix: always reference the final UI field name. See `qlik-naming-conventions` for cross-layer naming and the field rename layer pattern.

### Type sensitivity in element sets (Dual fields)
A field defined as `Dual('Yes', 1)` has both a text representation ("Yes") and a numeric one (1). Element sets distinguish:
- `{<Flag={1}>}` matches the numeric encoding only.
- `{<Flag={'Yes'}>}` matches the text encoding only.

If the data model has heterogeneous encoding (some records hold the numeric form, some the text form, both as Dual), the modifier matches only the matching subset. Use `Text(field)` and `Num(field)` to confirm encoding.

### Scope explosion via `{<>}`
`Sum({<>} [Amount])` ignores ALL selections, not just the field you intended to override. Easy to write when refactoring or copy-pasting. If only one field needs override, name it explicitly: `<Field={}>`.

### Element set as variable reference (missing quotes on string literal)
`{<Region={East}>}` is interpreted as "Region matches the value of variable `East`," not the literal string "East." If variable `East` doesn't exist, the modifier returns NULL silently. Always quote string literals: `{<Region={'East'}>}`.

### Wrong set operator vs. field modifier separator
`{<Year={2024}, Region={'East'}>}` (comma between field modifiers) is intersection — Year=2024 AND Region=East. `{<Year={2024}> + <Region={'East'}>}` (plus between sets) is union — Year=2024 OR Region=East. The two produce different results. The comma form is far more common; reach for `+` between full set modifiers only when union semantics are explicitly needed.

### Mismatched quoting (silent case mismatch)
`{<Country={'New Zealand'}>}` and `{<Country={"New Zealand"}>}` are NOT equivalent:
- Single quotes — exact, case-sensitive literal match.
- Double quotes — case-insensitive search; matches "New Zealand," "NEW ZEALAND," "new zealand."

Picking the wrong quote silently changes the result set.

---

## 9. Anti-Pattern Catalog

### Anti-Pattern: Missing Set Identifier When Using Operators

**Wrong:**
```
Sum({*<Year={2024}>} [Amount])
// The * operator requires a left operand (set identifier)
```

**Correct:**
```
Sum({$*<Year={2024}>} [Amount])
// Intersection of current selection ($) with Year=2024
```

### Anti-Pattern: Wrong Set Operator for the Scenario

**Wrong (intersection when union needed):**
```
Sum({<Status={'Active'}, Status={'Inactive'}>} [Amount])
// Same field with two modifiers — Qlik applies the last one (Inactive)
// Result: only Inactive rows, not both
```

**Correct (single modifier with comma-separated values is implicit union for the same field):**
```
Sum({<Status={'Active', 'Inactive'}>} [Amount])
// Status in {Active, Inactive}
```

**Correct (explicit union of two sets):**
```
Sum({<Status={'Active'}>+<Status={'Inactive'}>} [Amount])
```

### Anti-Pattern: Hardcoded Values Instead of Variables

**Wrong:**
```
Sum({<Year={2024}>} [Amount])
// Stale next year; manual updates required
```

**Correct:**
```
SET vCurrentYear = Num(Today(), 'YYYY');
Sum({<Year={$(vCurrentYear)}>} [Amount])
```

### Anti-Pattern: Redundant P() When Default Selection Is Intended

**Wrong:**
```
Sum({<Region={P(Region)}>} [Amount])
// P(Region) = currently possible Region values — same as default behavior
// No-op; misleading
```

**Useful counterpart:**
```
Sum({<Region={E(Region)}>} [Amount])
// E(Region) = excluded values — sales from regions NOT in the user's selection
```

### Anti-Pattern: Element Set Syntax Errors

**Wrong (missing quotes on strings):**
```
Sum({<Region={East, West}>} [Amount])
// Qlik tries to expand variables `East` and `West`; usually returns NULL
```

**Correct:**
```
Sum({<Region={'East', 'West'}>} [Amount])
```

**Wrong (brackets instead of braces around element set):**
```
Sum({<Region=[East, West]>} [Amount])
// Square brackets are for field/file names, not element sets
```

**Correct:**
```
Sum({<Region={'East', 'West'}>} [Amount])
```

### Anti-Pattern: SET Variable Containing Commas Passed to Variable Function

**Wrong:**
```
SET vRegionList = 'East', 'West';
SET vCleanRegion = Trim($1);
Sum({<Region={$(vCleanRegion($(vRegionList)))}>} [Amount])
// vRegionList expansion injects a comma into the $() parameter list
// $1 = 'East', $2 = 'West' — parameter parsing breaks
```

**Correct (drop the wrapping variable function):**
```
SET vRegionList = 'East', 'West';
Sum({<Region={$(vRegionList)}>} [Amount])
```

### Anti-Pattern: Forgetting Other Selections Are Still Active

**Wrong (assumes "year 2024" overrides everything):**
```
Sum({<Year={2024}>} [Amount])
// User selected Region=East, Customer=ABC
// Result: 2024 sales for East/ABC only — not "all of 2024"
```

**Clarify intent:**
```
// Truly "all 2024 regardless of other selections":
Sum({<Year={2024}, Region={}, Customer={}>} [Amount])

// "2024 respecting other selections" (most common intent):
Sum({<Year={2024}>} [Amount])    // comment that other selections still apply
```

### Anti-Pattern: Using TOTAL When Set Analysis is Needed

**Wrong:**
```
// User selected Region=East; you want ALL regions' totals
Sum(TOTAL [Amount])
// TOTAL only changes dimension scope, not selection scope
// Region=East still applies
```

**Correct:**
```
Sum({1} TOTAL [Amount])
// {1} = all data, ignoring selections; TOTAL = ignore chart dimensions
```

### Anti-Pattern: Comparing Field-to-Field Without Dollar-Sign Evaluation

**Wrong:**
```
Sum({<Year=Year>} [Amount])
// Right side is the field name, not a dimension value
// Parses but does not do what's intended
```

**Correct (filter to a single selected dimension value):**
```
Sum({<Year={$(=Only(Year))}>} [Amount])
// Only(Year) returns the selected year if exactly one is selected
// $(=...) evaluates and substitutes the result
```

### Anti-Pattern: Fictional `with` Operator

Set analysis has NO `with` keyword. Modifiers are comma-separated inside `<…>`, and set-level operators are `+`, `-`, `*`, `/`. Examples like `{<Year={2024} with Region={'East'}>}` (seen occasionally in AI-generated code) are invalid Qlik.

---

## 10. Sources

- help.qlik.com Cloud → Scripting → Chart functions → Set analysis (set syntax, identifiers, operators, modifiers)
- help.qlik.com Cloud → Set modifiers (`<Field={...}>` syntax, comparison operators, search strings, P()/E() functions)
- help.qlik.com Cloud → Implicit set operators (`+=`, `-=`, `*=`, `/=` field-level)
- help.qlik.com Cloud → Alternate states (state-name set identifier rules)
- help.qlik.com Cloud → Dollar-sign expansion (`$(variable)` and `$(=expression)` timing, parameter conventions)
- Henric Cronström, "Performance of Conditional Aggregations" (Qlik Design Blog) — set analysis vs. flag multiplication tradeoffs
- Bitmetric — set analysis P()/E() and search-string patterns
