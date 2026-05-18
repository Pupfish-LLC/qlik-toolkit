---
name: qlik-review-checklist
description: Complete QA checklist for validating Qlik development artifacts. Covers data model integrity, naming convention compliance, script quality, expression correctness, security gaps, cross-artifact consistency, blocked dependency audit, and data quality validation. Used by the qa-reviewer agent and also available for ad-hoc QA reviews.
user-invocable: false
---

# QA Review Checklist for Qlik

## Overview

This checklist provides comprehensive QA validation for Qlik development artifacts. It is consumed primarily by the `qa-reviewer` agent across four review scopes:

- **Data Model Review** — Data model specification validation (Critical severity only by default).
- **Script Review** — Load script + data model validation (Critical + Warning).
- **Expression Review** — Expression correctness validation (Critical + Warning).
- **Comprehensive Review** — All artifacts, all severities (Critical + Warning + Suggestion).

The checklist can also be used standalone for ad-hoc QA reviews.

## Severity Definitions

- **Critical** — Reload fails, data integrity violated, or fundamental design flaw. Includes expressions that are structurally invalid and guaranteed to produce incorrect results (e.g., nested aggregation without `Aggr()`, TOTAL placed inside set analysis braces).
- **Warning** — Should be fixed before moving forward. Potential data quality issue, naming inconsistency, performance degradation, or best-practice violation.
- **Suggestion** — Improvement recommendation. Code clarity, minor optimization, or pattern consistency.

## Review Pass Types

| Pass | Scope | Applicable Categories | Severity Focus |
|---|---|---|---|
| **Data Model** | Data model specification | Data Model Integrity, Naming Compliance, Cross-Artifact Consistency (basic) | Critical only |
| **Script** | Load scripts + final loaded model | Script Syntax, Performance, Data Model Integrity, Naming Compliance, Cross-Artifact Consistency | Critical + Warning |
| **Expression** | Expression catalog + variables file | Expression Correctness, Naming Compliance, Cross-Artifact Consistency | Critical + Warning |
| **Comprehensive** | All available artifacts | All categories (9 total) | Critical + Warning + Suggestion |

## Validation Categories (9 total)

1. **Script Syntax** (9 items) — Dollar-sign expansion safety, SQL construct prohibition, function arguments, block balance, NullAsValue scope, RENAME collisions.
2. **Performance** (3 items) — Redundant disk reads, repeated expressions, temp table cleanup.
3. **Data Model Integrity** (8 items) — Synthetic keys, associations, auto-concatenation, QUALIFY interaction, null handling, grain alignment, circular references, key consistency.
4. **Naming Convention Compliance** (5 items) — Entity-prefix dot notation, key field conventions, variable naming, table naming, cross-layer consistency.
5. **Expression Correctness** (7 items) — Set analysis syntax, TOTAL qualifier, null handling, field references, dollar-sign expansion, calculation conditions, structurally invalid aggregation.
6. **Security** (5 items) — PII exposure, Section Access patterns, reduction field handling, completeness, OMIT field correctness. (Section Access teaching is out of scope for this plugin version — a dedicated Section Access skill is pending a rewrite.)
7. **Cross-Artifact Consistency** (4 items) — Expressions reference existing fields, viz specs reference existing expressions, scripts use platform subroutines, field name consistency.
8. **Blocked Dependency Audit** (3 items) — Placeholder documentation, downstream flags, dependency tracker alignment.
9. **Data Quality Validation** (5 items) — Null rate analysis, referential integrity, value distribution, row counts, orphaned records.

## How to Use This Checklist

1. **Load `checklist.md`** for detailed check items, verification methods, and finding format examples.
2. **For each applicable review pass**, iterate through checklist items marked for that pass.
3. **Document all findings** using the standardized Finding Format below.
4. **Organize findings** by category and severity in the output report.
5. **Flag execution validation requests** — for Script or Expression reviews, pause and surface specific validation requests to the developer when reload-time verification is needed.
6. **Verify Critical finding resolution** — for Comprehensive reviews, ensure all Critical findings from earlier passes are resolved.

## Finding Format

```
[ID]: [Title]
- Severity: [Critical | Warning | Suggestion]
- Category: [category_name]
- Location: [artifact_path]:[line number] or [location description]
- Finding: [Detailed description of what is wrong]
- Impact: [What breaks or what negative consequence occurs]
- Recommended Fix: [Specific action to resolve]
```

**Example:**

```
[S-1.1]: Dollar-sign expansion with nested function
- Severity: Critical
- Category: Script Syntax
- Location: scripts/load-main.qvs:42
- Finding: $(variable(...)) contains ApplyMap with comma-separated arguments
- Impact: Variable expansion will fail during reload, breaking script execution
- Recommended Fix: Rewrite inline without variable wrapping to avoid comma nesting
```

## Review Pass Applicability Summary

| Category | Data Model | Script | Expression | Comprehensive |
|---|:---:|:---:|:---:|:---:|
| Script Syntax | — | ✓ | — | ✓ |
| Performance | — | ✓ | — | ✓ |
| Data Model Integrity | ✓ | ✓ | — | ✓ |
| Naming Convention Compliance | ✓ | ✓ | ✓ | ✓ |
| Expression Correctness | — | — | ✓ | ✓ |
| Security | — | ✓ | — | ✓ |
| Cross-Artifact Consistency | (basic) | ✓ | ✓ | ✓ |
| Blocked Dependency Audit | — | (light) | (light) | ✓ |
| Data Quality Validation | — | ✓ | — | ✓ |

## See Also

- **`checklist.md`** — Full detailed checklist with all items (1.1–9.5), verification methods, and examples.
- **`qlik-naming-conventions`** — Field naming, key conventions, variable naming, cross-layer strategies.
- **`qlik-load-script`** — Script syntax rules, QVD operations, incremental loads, null handling.
- **`qlik-data-modeling`** — Data model design patterns, synthetic key prevention, grain management.
- **`qlik-expressions`** — Expression syntax, set analysis, null handling in measures.
- **`qlik-performance`** — Optimization strategies, QVD load modes, preceding LOAD patterns.
- **`data-quality-validator`** — Post-load data quality validation query patterns.
