# Variable Rules Reference

Canonical home for variable mechanics in expression catalogs: SET vs LET decision criteria, dollar-sign expansion comma rules, trailing-semicolon discipline, and the conventional structure of an `expression-variables.qvs` file. Companion to `qlik-expressions/SKILL.md` Section 6 (dollar-sign expansion).

For variable naming conventions (the `v` prefix, variable-name-mirrors-measure-name pattern, cross-layer alignment), see `qlik-naming-conventions` § 4. For script-context SET/LET behavior (function-call evaluation gotchas, null variable expansion), see `qlik-load-script` § 2.

## 1. SET vs LET Decision Criteria

The choice between `SET` and `LET` is governed by **when** the right-hand side should evaluate.

| Use | When | Example |
|---|---|---|
| `SET` | The right-hand side is an expression template — referenced text expanded at use time | `SET vRevenue = Sum([Amount]);` — Sum is not evaluated at script load; it expands at chart render |
| `SET` | The right-hand side contains `$1`, `$2`, ... parameter placeholders for a variable function | `SET vDualBool = IF(Match($1, 'true') > 0, Dual('Yes', 1), Dual('No', 0));` — placeholders bind at invocation: `$(vDualBool([Field]))` |
| `SET` | The right-hand side references other variables that should expand at use time | `SET vAvgValue = $(vRevenue) / $(vOrderCount);` — the `$(vRevenue)` and `$(vOrderCount)` substitutions happen at chart render |
| `LET` | The right-hand side is a value to compute once at script-load time, with no later re-evaluation | `LET vDataLoadDate = Today();` — captures Today() at the moment the script runs |
| `LET` | The right-hand side is arithmetic or function evaluation needed as a literal value downstream in the script | `LET vRowCount = NoOfRows('MyTable');` — count is captured immediately for use in script logic |

### LET Evaluation Semantics

`LET` evaluates the right-hand side once at script-load time and substitutes that fixed value wherever the variable is later referenced. The value does not change during the session.

Per help.qlik.com — Let statement: "The Let statement evaluates the string and assigns 7 to the variable" — the expression is evaluated once during script execution and the resulting value is stored in the variable. SET, in contrast, "stores the expression itself as a string without evaluation, allowing it to be re-evaluated each time the variable is referenced."

**Critical consequence — never use LET for dynamic UI expressions:**

```qlik
// WRONG -- evaluated once at script load; never updates as time passes
LET vCurrentYear = Year(Today());

// RIGHT -- expression text stored; re-evaluated at chart render time, 
// always reflects the current date
SET vCurrentYear = Year(Today());
```

Variables referenced in chart expressions should almost always use `SET`. The expression text is stored once at load and the actual evaluation happens at chart render — so `vCurrentYear` always reflects the current year, not the year at the last reload.

LET is reserved for values that need to be a literal in the script itself (counts for FOR loops, date bounds for incremental loads, flags computed from system state) — places where the value will never be re-evaluated by a chart.

### SET Does Not Evaluate Function Calls

A common load-script gotcha that affects variable definition files: SET preserves the right-hand side as literal text, including function calls. To assign a computed value, use LET:

```qlik
// WRONG: assigns the literal string "Chr(37)" to vHidePrefix
SET vHidePrefix = Chr(37);

// RIGHT options:
LET vHidePrefix = Chr(37);     // Evaluates Chr(37) -> '%'
SET vHidePrefix = '%';         // Literal '%' directly
```

This applies to all function calls on the right side of SET, including `Chr()`, `Num()`, `Date()`, `Today()`, `Time()`. See `qlik-load-script` § 2 for the full script-context treatment.

## 2. Dollar-Sign Expansion Comma Rules

Inside `$(varname(args))`, commas are **parameter delimiters**, not expression argument separators. This is the single most common source of reload errors and silent bugs in variable-heavy scripts.

Per help.qlik.com — Dollar-sign expansion using parameters: parameter placeholders `$1`, `$2`, `$3` are filled by a comma-separated list at invocation time. `$0` returns the number of parameters actually passed.

### The Comma Trap

If an argument to a variable function itself contains a comma (because it's an expression like `ApplyMap`, `IF`, `PurgeChar`, or `Concat`), the engine splits the call at that comma:

```qlik
SET vCleanNull = IF(IsNull($1) OR Len(Trim($1)) = 0, Null(), Trim($1));

// WRONG -- ApplyMap's commas break parameter parsing
$(vCleanNull(ApplyMap('MyMap', field, 'default')))
// The engine sees: 
//   $1 = ApplyMap('MyMap'
//   $2 = field
//   $3 = 'default')
// Result: parse error or unexpected behavior, often silent.

// RIGHT -- write the logic inline when the argument contains commas
IF(IsNull(ApplyMap('MyMap', field, 'default')),
   Null(),
   Trim(ApplyMap('MyMap', field, 'default')))
```

**Functions that commonly trigger the trap when passed as variable arguments:**
- `ApplyMap('Map', key, default)` — three commas
- `PurgeChar(field, 'chars')` — one comma
- `IF(cond, then, else)` — two commas
- `Concat(field, delim)` — one comma
- Any `Match()`, `WildMatch()`, `MixMatch()` call with multiple values

**Rule:** only pass simple field references or literal values (no commas) as arguments to variable functions. If the value needs a comma-containing expression, write the equivalent logic inline at the call site and add a comment explaining why.

### Workaround via Chr(44)

A rare workaround uses `Chr(44)` (ASCII comma) constructed in a LET, but this is brittle and harder to read than inlining. Reserve it for cases where the same comma-containing logic appears many times and inlining would create unmaintainable duplication:

```qlik
LET vComma = Chr(44);
// Then use $(vComma) inside the variable definition wherever a literal 
// comma is needed -- but the parameter-delimiter behavior at the call 
// site is unchanged.
```

In practice, this is more often a sign that the logic should be a load-time mapping table or a derived field, not a chart-time expression.

### Indirect Dollar-Sign Expansion

`$(=expression)` forces immediate evaluation and substitutes the result at parse time:

```qlik
// $(vCurrentYear) substitutes the variable's stored text
{<Year={$(vCurrentYear)}>}

// $(=Max(Year)) evaluates Max(Year) now and substitutes the result
{<Year={$(=Max(Year))}>}
```

The `=` form is useful for dynamic labels and indirect set modifiers that depend on current selections. The comma rule still applies — `$(=expr)` cannot accept comma-containing arguments either.

See `qlik-expressions/references/set-analysis.md` § Dollar-Sign Expansion Inside Set Modifiers for dynamic set-modifier patterns including the comma trap in that context.

## 3. Trailing Semicolons

Every variable definition must end with a semicolon. Missing semicolons cause the parser to concatenate the next statement into the current one — sometimes producing a syntax error, sometimes producing a silently corrupted definition.

```qlik
// WRONG -- missing semicolon after vRevenue
SET vRevenue = Sum([OrderLine.Amount])
SET vOrderCount = Count(DISTINCT [Order.Key]);

// The parser sees:
//   SET vRevenue = Sum([OrderLine.Amount])SET vOrderCount = ...
// Outcome: error, or vRevenue assigned a corrupted template.

// RIGHT
SET vRevenue = Sum([OrderLine.Amount]);
SET vOrderCount = Count(DISTINCT [Order.Key]);
```

This is mechanical — review every line of an `expression-variables.qvs` file for the terminating semicolon before reload.

## 4. expression-variables.qvs Organization

The `expression-variables.qvs` file is executable Qlik script invoked via `$(Include=)` or `$(Must_Include=)` from the main script. Convention organizes it for readability and maintenance.

### Section Order

1. **Configuration variables** — load-context values (current period, today's date, fiscal year start) — set first because everything else may reference them.
2. **Base measures** — single-source aggregations with no dependencies (`Sum([Amount])`, `Count(DISTINCT [Order.Key])`).
3. **Derived measures** — expressions that reference base measures via dollar-sign expansion (`$(vRevenue) / $(vOrderCount)`).
4. **Set-analysis measures** — measures with set modifiers (current-year revenue, excluded-status counts, etc.).
5. **Calculation conditions** — boolean expressions for object-level calculation conditions.
6. **Field-reference variables** — `SET vCustomerRegion = [Customer.Region];` style indirection wrappers.
7. **Calculation-weight or grouping comment headers** — optional structural markers for navigation.

### Comment Block Convention

Use prominent comment blocks to mark functional groupings. Treat them as navigation aids — a developer scrolling a 200-line variables file should be able to find the financial-measures section at a glance.

```qlik
// =============================================
// --- Configuration ---
// =============================================
SET vCurrentYear = Year(Today());
SET vCurrentMonth = Month(Today());
SET vToday = Today();
LET vDataLoadDate = Now();

// =============================================
// --- Base Measures ---
// =============================================
SET vRevenue = Sum([OrderLine.Amount]);
SET vOrderCount = Count(DISTINCT [Order.Key]);
SET vCustomerCount = Count(DISTINCT [Customer.Key]);

// =============================================
// --- Derived Measures ---
// =============================================
SET vAvgOrderValue = $(vRevenue) / $(vOrderCount);
SET vRevenuePerCustomer = $(vRevenue) / $(vCustomerCount);

// =============================================
// --- Time Intelligence ---
// =============================================
SET vRevenue_CurrentYear = Sum({<Year={$(vCurrentYear)}>} [OrderLine.Amount]);
SET vRevenue_PriorYear = Sum({<Year={$(=$(vCurrentYear)-1)}>} [OrderLine.Amount]);

// =============================================
// --- Calculation Conditions ---
// =============================================
SET vCondition_SingleYear = (GetSelectedCount(Year) = 1);
SET vMessage_SingleYear = 'Select exactly one year';

// =============================================
// --- Field-Reference Variables ---
// =============================================
SET vCustomerRegion = [Customer.Region];
SET vProductCategory = [Product.Category];
```

### Dependency Ordering

Within each section, place variables in dependency order: simple aggregations before expressions that reference them. The dollar-sign expansion `$(vRevenue)` substitutes the variable's text at chart render time, but author-time clarity benefits from defining vRevenue above vAvgOrderValue.

This is conventional, not enforced — variable order does not affect runtime behavior because chart-time expansion looks up the variable when needed. But a reader auditing the file expects to read top-down and see the building blocks before the composites.

### File Boundary Discipline

The variables file should contain only `SET` / `LET` statements and comment blocks. Avoid embedding LOAD statements, RESIDENT operations, or anything that touches the data model — those belong in dedicated script files. A variables file that contains data operations is harder to reuse across apps and harder to reason about.

## 5. Failure Modes

**SET with function calls in the right-hand side.** `SET vToday = Today();` assigns the literal string "Today()", not the current date. Use LET when the value must be computed at script load: `LET vToday = Today();`. See Section 1.

**LET for dynamic UI expressions.** `LET vCurrentYear = Year(Today());` freezes the year at the last reload. Use SET. See Section 1.

**Comma-containing expression passed as variable function argument.** See Section 2 — silent parse error or wrong result. Write inline at the call site.

**Missing trailing semicolon.** See Section 3 — statement concatenation, often silent corruption.

**Variable referencing an intermediate-layer field name.** `SET vCustomerRegion = [Account.Region];` references a Transform-layer name that no longer exists after the DataModel rename. The expression evaluates to NULL silently. Always reference final UI/DataModel-layer field names. See `qlik-naming-conventions` § 7.

**`SET vTotal = $(vRevenue) + $(vOrderCount);` with missing parentheses.** Dollar-sign expansion substitutes the variable's raw text. If `vRevenue` is `Sum([Amount])` and `vOrderCount` is `Count(DISTINCT [Order.Key])`, the expansion yields `Sum([Amount]) + Count(DISTINCT [Order.Key])` — valid but the precedence is unparenthesized. For ratios or compound expressions, wrap each `$(...)` reference in parentheses: `($(vRevenue)) / ($(vOrderCount))`.

## 6. Catalog Documentation Convention

When an expression depends on variable indirection, document:
- **Variable** — the variable name backing the measure.
- **SET vs LET** — usually SET for chart expressions; flag any LET uses with a note explaining why.
- **Dependencies** — which other variables the expression references via dollar-sign expansion.
- **Comma considerations** — if the expression has comma-containing arguments to variable functions, document that the logic is inlined for parser safety.

Example catalog entry note:
```
Variable: vAvgOrderValue
SET (chart-time expansion). Depends on vRevenue and vOrderCount 
(both base measures). Wrapped in parentheses to enforce precedence:
($(vRevenue)) / ($(vOrderCount)).
```

## Source Notes

- LET evaluation semantics: help.qlik.com — Let statement (Sense on Windows, current build) — tier 1.
- SET preserves text: same source, contrasting Set statement — tier 1.
- Parameter placeholders `$1`–`$N`, `$0` parameter count: help.qlik.com — Dollar-sign expansion using parameters — tier 1.
- Comma-as-parameter-delimiter: same source — tier 1. The "comma trap" failure mode is the direct consequence; tier-1 docs do not call it out as a trap, but the mechanism is documented.
- SET-does-not-evaluate-function-calls trap: practitioner-documented in `qlik-load-script` § 2; aligns with tier-1 Set statement documentation.
