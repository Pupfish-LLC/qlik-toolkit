# Null Handling Patterns for Qlik Scripts

Three distinct strategies for handling nulls in Qlik load scripts. Each addresses a different type of null problem. Using the wrong strategy for a given situation produces subtle data quality bugs.

---

## vCleanNull Variable Function

### The Problem

Source data from ETL pipelines, JSON ingestion, data lakes, and API exports commonly contains literal strings that represent null: `"null"`, `"NaN"`, `"none"`, `"n/a"`, `"[null]"`, and empty strings. These are NOT SQL NULLs. Qlik's `IsNull()` function does NOT catch them. They appear as valid string values in filter panes and break aggregations.

### The Pattern

```qlik
// SET preserves the template -- $1 placeholder stays unevaluated until expansion
SET vCleanNull = IF(IsNull($1) OR Len(Trim($1)) = 0
    OR Match(Lower(Trim($1)), 'null', 'nan', 'none', 'n/a', '[null]'),
    Null(), Trim($1));
```

### Usage

```qlik
// Simple field -- pass field name as $1:
$(vCleanNull(customer_name)) AS [Customer.Name],
$(vCleanNull(email_address)) AS [Customer.Email],
$(vCleanNull(phone_number))  AS [Customer.Phone]
```

### Why SET, Not LET

`SET` preserves the right side as a literal string template. The `$1` placeholder remains unevaluated until the variable is expanded with `$(vCleanNull(field))`. `LET` would try to evaluate `$1` immediately at definition time and fail.

### Limitation: Commas in Arguments

The variable function CANNOT wrap expressions containing commas. Inside `$()`, commas separate parameters. If the argument contains a function with commas (ApplyMap, PurgeChar, IF), the call breaks.

```qlik
// WRONG -- PurgeChar has a comma, breaks the variable call:
$(vCleanNull(PurgeChar(given_names, '[]{}' & Chr(34))))

// RIGHT -- write the null check inline with a comment explaining why:
// Cannot use vCleanNull here (comma in PurgeChar args)
IF(IsNull(PurgeChar(given_names, '[]{}' & Chr(34)))
   OR Len(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))) = 0
   OR Match(Lower(Trim(PurgeChar(given_names, '[]{}' & Chr(34)))),
            'null', 'nan', 'none', 'n/a', '[null]'),
   Null(),
   Trim(PurgeChar(given_names, '[]{}' & Chr(34))))  AS [Name.Given]
```

### When to Use

- Fields from ETL pipelines, data lakes, or API ingestion where nulls may be string-encoded
- Any field where you've observed literal "null" or "NaN" strings in the data
- As a default defensive measure on all string fields from external sources

### When NOT to Use

- Fields where the literal string "null" is a valid business value (rare but possible)
- Key fields (use explicit null checks and TRACE warnings instead)
- Numeric fields (use IsNull() directly, string-encoded nulls in numeric fields indicate a type coercion issue that should be investigated)

### Complete Variable Function File

See `script-templates/clean-null-function.qvs` for the full set of null-cleaning utilities including vCleanNull, vCleanDate, vCleanNumeric, and vDualBool.

**vDualBool overview:** Converts a boolean-like field to `Dual()` with text display and numeric value. `Dual('Active', 1)` for true-like values, `Dual('Inactive', 0)` for false, `Dual('Unknown', -1)` for NULL. This gives text in filter panes, numeric for `Sum()`, and correct sort order. The function matches common true values ('true', 'yes', 'y', '1', 'active', 'enabled'). For domain-specific true values like 'approved' or 'confirmed', write a custom IF instead. See `clean-null-function.qvs` for the full definition.

---

## NullAsValue Patterns

### The Problem

Sparse dimension fields where many records have NULL values. In Qlik filter panes, NULL values appear as "-" and cannot be selected alongside non-null values in the same selection set. Users want to see "No Entry" or "Unknown" as a selectable value.

### The Pattern

```qlik
SET NullValue = 'No Entry';
NullAsValue [Customer.Region], [Customer.Segment], [Product.SubCategory];

[Customers]:
LOAD
    customer_id    AS [Customer.Key],
    customer_name  AS [Customer.Name],
    region         AS [Customer.Region],
    segment        AS [Customer.Segment]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Always reset after each table load unless you intentionally want
// the null replacement to persist across subsequent LOADs for these fields.
// Forgetting to reset is the most common NullAsValue bug.
NullAsNull *;
SET NullValue =;
```

### Critical Rules

1. **Field-specific:** NullAsValue only affects the named fields. Other fields in the same LOAD retain normal null behavior.

2. **Stateful:** Once declared, NullAsValue persists for those fields across ALL subsequent LOADs until explicitly reset with `NullAsNull`. This means:
   - If you load `[Customer.Region]` in multiple tables, NullAsValue applies to ALL of them unless reset between LOADs
   - Failing to reset when you only wanted it for one table means unintended null replacement downstream

3. **Use the name the field has in the final data model:** When a LOAD renames a field with `AS`, use the output alias (the name the field will have after loading) in the NullAsValue declaration. The source column name only works if you don't rename. This is not explicitly called out in help.qlik.com but is consistent with how NullAsValue targets fields by their loaded name; verify empirically in your environment if you rely on it.

```qlik
// PREFERRED -- uses the loaded field name (the AS alias):
NullAsValue [Customer.Region];
LOAD region AS [Customer.Region] FROM ...;

// AMBIGUOUS -- uses the source column name; behavior when AS is in use
// is not documented and should be tested before relying on it:
NullAsValue region;
LOAD region AS [Customer.Region] FROM ...;
```

4. **Reset protocol:** Reset with BOTH statements:
```qlik
NullAsNull *;       // Resets all fields to normal null behavior
SET NullValue =;    // Clears the replacement string
```

### When to Use

- Sparse dimension fields where NULL should be a selectable filter value
- Fields that serve as dimension headers in filter panes
- Classification fields where "Unknown" or "Not Assigned" is a meaningful category

### When NOT to Use

- **Key fields:** NullAsValue converts NULL to a string ('No Entry'). A key field containing 'No Entry' will associate with OTHER tables' 'No Entry' values, creating false associations. If a key is NULL, that's a data quality issue to investigate, not mask.

- **Measure fields intended for Sum/Avg:** NullAsValue converts NULL to a string. `Sum()` on a field containing the string 'No Entry' produces 0 (the string is treated as 0 in numeric context) but `Avg()` treats it as a valid value, skewing the average downward. NULL values are correctly excluded from both Sum and Avg by default.

- **Fields used in date arithmetic:** The string 'No Entry' in a date field breaks date calculations.

### Scope Management Example

```qlik
// Apply NullAsValue for Customer table only
SET NullValue = 'Unknown';
NullAsValue [Customer.Region], [Customer.Segment];

[Customers]:
LOAD customer_id AS [Customer.Key],
     region AS [Customer.Region],
     segment AS [Customer.Segment]
FROM [lib://QVDs/Customers.qvd] (qvd);

// Reset before loading Product table (Product.Category should NOT get 'Unknown')
NullAsNull *;
SET NullValue =;

// Product NULLs stay as NULL (correct for this table)
[Products]:
LOAD product_id AS [Product.Key],
     category AS [Product.Category]
FROM [lib://QVDs/Products.qvd] (qvd);
```

---

## Null Guards on Date Arithmetic

### The Problem

Per Qlik's null-value-handling documentation, NULL propagates through arithmetic: `Today() - NULL` returns NULL, and `Floor(NULL / 365.25)` also returns NULL. So a genuinely NULL date does not by itself produce a nonsense age -- it produces a correctly NULL age. The real problem is **non-NULL garbage dates** that upstream systems substitute for missing values:

- **Sentinel dates** -- sources that use `1900-01-01`, `1901-01-01`, or `1970-01-01` to represent "unknown" instead of NULL. These are valid dates, so NULL propagation does not protect you; `Today() - '1900-01-01'` returns ~46,000 and `/ 365.25` returns ~125.
- **String-encoded nulls coerced upstream** -- a source column with the literal string "null" that was silently cast to a date somewhere in the pipeline.
- **Future dates from data entry bugs** -- e.g., `registration_date = 2099-01-01` produces a large negative tenure.
- **Zero dates** -- some databases store `0000-00-00`, which may round-trip as December 30, 1899 (Qlik's epoch zero), producing a ~125 year tenure.

```qlik
// Looks defensible but still produces garbage when source uses sentinel dates:
Floor((Today() - registration_date) / 365.25) AS [Customer.TenureYears]
// If registration_date = 1900-01-01 (sentinel for "unknown"): TenureYears = 125
```

### The Pattern

Guard date arithmetic against **both** NULL and known sentinel/out-of-range values. The NULL check is cheap defensive insurance; the range check is what actually catches the sentinel-date bug:

```qlik
// RIGHT -- guard against NULL AND sentinel/out-of-range dates:
IF(IsNull(registration_date)
    OR registration_date < MakeDate(1901, 1, 2)       // catches epoch-zero, 1900-01-01 sentinels
    OR registration_date > Today(),                   // catches future-date data entry bugs
   Null(),
   Floor((Today() - registration_date) / 365.25)) AS [Customer.TenureYears]
```

### Common Date Arithmetic Patterns with Guards

```qlik
// Customer tenure (guards both NULL and sentinel/future dates)
IF(IsNull(registration_date)
    OR registration_date < MakeDate(1901, 1, 2)
    OR registration_date > Today(),
   Null(),
   Floor((Today() - registration_date) / 365.25)) AS [Customer.TenureYears]

// Days since last order (NULL-safe by default, but guard sentinel dates)
IF(IsNull(last_order_date) OR last_order_date < MakeDate(1901, 1, 2), Null(),
    Today() - last_order_date) AS [Customer.DaysSinceLastOrder]

// Date difference between two fields (NULL propagates, so IsNull is optional
// but explicit is clearer; add range guards if sentinels are possible)
IF(IsNull(start_date) OR IsNull(end_date), Null(),
    end_date - start_date) AS [Duration.Days]

// Tenure in months (guard sentinels and future hires)
IF(IsNull(hire_date)
    OR hire_date < MakeDate(1901, 1, 2)
    OR hire_date > Today(),
   Null(),
   Floor((Today() - hire_date) / 30.44)) AS [Employee.TenureMonths]
```

### Why This Is Easy to Miss

When the source actually returns NULL, Qlik's NULL propagation produces the correct result (NULL) without any guard -- so a naive script passes testing during development when the test data is clean. The bug only surfaces in production when an upstream system substitutes a sentinel date like `1900-01-01` for missing values. The calculation runs without error, the result is a plausible-looking number (125 is a valid age, just wrong), and the bug only becomes visible when someone notices impossible values in reports or when aggregations are skewed by phantom centenarians.

### When to Apply

Any expression that involves:
- Subtraction between dates: `dateA - dateB`
- Division of a date difference: `(dateA - dateB) / N`
- Date functions on potentially-null fields: `Year(date_field)`, `Month(date_field)`

**Rule of thumb:** If a field is used as an operand in date math and it can ever be NULL, wrap the entire expression in an IsNull guard.

---

## Defensive Null Handling Strategy

### Decision Framework

| Field Type | Null Source | Strategy | Example |
|---|---|---|---|
| String dimension from external source | String-encoded nulls ("null", "NaN") | vCleanNull | `$(vCleanNull(region)) AS [Region]` |
| Sparse dimension for filter panes | Genuine SQL NULLs | NullAsValue | `NullAsValue [Customer.Segment]` |
| Date/numeric used in calculations | Any null source | IsNull guard | `IF(IsNull(date), Null(), ...)` |
| Boolean field | NULL = unknown state | Dual with -1 | `$(vDualBool(is_active, Active, Inactive))` |
| Key field | Any null source | **Never mask.** TRACE a warning. | Null key = data quality issue |

### Layered Application

In a typical extraction script, you may use all three strategies on different fields in the same LOAD:

```qlik
SET NullValue = 'No Entry';
NullAsValue [Customer.Region], [Customer.Segment];

[Customers]:
LOAD
    customer_id                                           AS [Customer.Key],
    $(vCleanNull(customer_name))                          AS [Customer.Name],
    region                                                AS [Customer.Region],
    segment                                               AS [Customer.Segment],
    IF(IsNull(registration_date)
        OR registration_date < MakeDate(1901, 1, 2)
        OR registration_date > Today(), Null(),
       Floor((Today() - registration_date) / 365.25))    AS [Customer.TenureYears],
    $(vDualBool(is_active, Active, Inactive))             AS [Customer.IsActive]
RESIDENT [_RawCustomers];

NullAsNull *;
SET NullValue =;
```

In this example:
- `customer_id`: No null masking (key field, nulls indicate data issues)
- `customer_name`: vCleanNull (catches "null" strings from upstream)
- `region`, `segment`: NullAsValue (sparse dimensions, need filter pane display)
- `registration_date`: IsNull guard + sentinel-date range check (used in tenure calculation)
- `is_active`: Dual boolean with Unknown/-1 for NULL
