---
name: qlik-review-checklist
description: "Catalog of failure classes that appear in Qlik Sense development artifacts, with severity model and finding-format contract. Covers script syntax errors, data model integrity issues (synthetic keys, circular references, grain misalignment), naming convention violations, expression correctness gaps, security misconfigurations (Section Access, PII), cross-artifact inconsistency, blocked dependency tracking, and post-load data quality. Load when reviewing a Qlik artifact (data model spec, load script, expression catalog, visualization spec, or full app), running a QA pass before sign-off, classifying defect severity, formatting findings for remediation, or deciding which checks apply to a given review scope."
user-invocable: false
---

# Qlik Review Checklist

## Overview

This skill is a Qlik QA **knowledge catalog**: failure classes that appear in Qlik development artifacts, the severity at which each should be flagged, and the finding format used to report them. Reviewers (human or agent) use it to classify what they see and write findings that a developer can act on without further conversation.

The skill catalogs *what can go wrong*. It does not re-teach the canonical patterns themselves — each category points back to its canonical home (e.g., synthetic-key resolution lives in `qlik-data-modeling`, set analysis syntax lives in `qlik-expressions`). The `references/checklist.md` reference contains the full per-item detail.

## Severity Model

Severity is a **field-experience classification**, not a Qlik-documented hierarchy. Qlik Sense itself reports only reload errors and warnings at the engine level; the three-tier model below reflects the practical impact of issues on a development cycle.

- **Critical** — Reload fails, data integrity is silently violated, or a design flaw blocks the artifact from being trusted. Examples: SQL constructs inside `LOAD`, dollar-sign expansion with comma-containing nested functions, synthetic keys, structurally invalid nested aggregation (no `Aggr()`), PII loaded without governance documentation. Section Access failure-class severity is not asserted here — defer to `help.qlik.com` Cloud Section Access docs (https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_Hub/Scripting/Security/manage-security-with-section-access.htm).
- **Warning** — Should be fixed before sign-off. Issue produces wrong results in some scenarios, degrades performance noticeably, violates project naming conventions, or leaves a foreseeable maintenance trap. Examples: date arithmetic without null guard, `QUALIFY` double-prefix on already-prefixed fields, key field naming that breaks the `%` / `_key` convention, repeated complex expressions in the same `LOAD`.
- **Suggestion** — Improvement opportunity. Code clarity, minor optimization, placeholder documentation, or pattern consistency. Examples: temp tables with no `DROP`, missing TRACE milestones, unexplained variable abbreviations.

**Severity escalation rules:**

- **Null handling on a key field** escalates from Warning to Critical, because nulls in associations break the data model rather than displaying as blanks.
- **TOTAL qualifier placed inside set-analysis braces** escalates from Warning to Critical, because the expression is structurally invalid and will not produce intended results. See `qlik-expressions/references/total-qualifier.md` for the canonical placement rules.
- **Synthetic keys** are always Critical regardless of size, because they indicate the model intent has diverged from the loaded structure.

## Failure Class Catalog (9 categories)

Each category below summarizes what to look for and points to the canonical home where the correct pattern is taught. Full item-by-item detail (severity, verification method, finding-format template) is in `references/checklist.md`.

### 1. Script Syntax (7 items)

What fails: reload errors and silent data failures from SQL syntax in `LOAD`/`RESIDENT`, dollar-sign expansion with comma-containing functions, function argument mistakes, unbalanced blocks, `NullAsValue` scope leaks, `RENAME FIELD` collisions, and semicolons inside `TRACE` messages.

Severity: mostly Critical (reload failures). `NullAsValue` scope issues are Warning unless they target keys or measures (then Critical).

Canonical homes:
- SQL constructs not valid in `LOAD`/`RESIDENT` — `qlik-load-script` → `references/sql-constructs.md`
- Dollar-sign expansion comma rule, SET vs LET — `qlik-load-script` Section 3 and `qlik-expressions` → `references/variable-rules.md`
- TRACE semicolon trap, ScriptError patterns — `qlik-load-script` → `references/error-handling.md`
- NullAsValue scope — `qlik-load-script` → `references/null-handling.md`

### 2. Performance (3 items)

What fails: redundant disk reads (same QVD loaded multiple times), repeated complex expressions in the same `LOAD`, and missing `DROP TABLE` for temp tables prefixed `_`.

Severity: Warning. These don't break the reload but waste memory and time.

Canonical home: `qlik-performance` Sections 3-4 (Script Load Optimization, Expression Calculation Optimization) and `qlik-load-script` → `references/qvd-operations.md` (Narrow Before STORE).

### 3. Data Model Integrity (8 items)

What fails: synthetic keys, association-direction errors, auto-concatenation traps, `QUALIFY` double-prefix interactions, null-handling gaps that break aggregations or associations, grain misalignment producing cartesian products, circular references, and inconsistent key resolution across tables.

Severity: mostly Critical (synthetic keys, circular references, auto-concatenation, association integrity always Critical). Null handling and key resolution consistency are Warning unless on keys (then Critical).

Canonical homes:
- Synthetic keys, circular references, `QUALIFY` discipline — `qlik-data-modeling` → `references/anti-patterns.md`
- Null handling in scripts — `qlik-load-script` → `references/null-handling.md`
- Grain alignment, bridge tables, key strategy — `qlik-data-modeling` (main SKILL body)

### 4. Naming Convention Compliance (5 items)

What fails: non-key fields not using entity-prefix dot notation, key fields missing the `%` prefix or `_key` suffix, variables missing the `v` prefix, table names violating project convention, and field names that drift inconsistently across source → extract → transform → model → UI layers.

Severity: Warning. Naming violations rarely break reloads but compound into a maintenance debt that's expensive to repay later.

Canonical home: `qlik-naming-conventions` (all sections).

### 5. Expression Correctness (7 items)

What fails: invalid set analysis syntax (modifier brackets, value types, dollar-sign expansion), TOTAL qualifier misplacement, null handling gaps in aggregations, references to fields not in the data model, dollar-sign expansion comma rule violations in SET variables, calculation conditions without paired messages, and nested aggregations without `Aggr()`.

Severity: Critical for syntax errors, structurally invalid nested aggregation, and broken field references. Warning for TOTAL clarity issues and incomplete calculation conditions.

Canonical homes:
- Set analysis syntax and anti-patterns — `qlik-expressions` → `references/set-analysis.md`
- TOTAL placement rules — `qlik-expressions` → `references/total-qualifier.md`
- Aggr() nesting patterns — `qlik-expressions` → `references/aggregation-patterns.md`
- Null handling in expressions — `qlik-expressions` SKILL.md Section 9

### 6. Security (5 items)

What fails: PII fields loaded without governance documentation. Section Access failure classes (STAR statement declaration, reduction-field case alignment, table completeness, OMIT correctness) are deferred to `help.qlik.com` — see `references/checklist.md` items 6.2-6.5 for the deferral pointers.

Severity: PII exposure flagging remains in scope at the project-governance level. Per-failure-class severity for Section Access items is not asserted here — consult `help.qlik.com` directly for current mechanics.

Canonical home: A dedicated Section Access skill is **out of scope for this plugin version** pending a rewrite against current Qlik Cloud documentation. For active Section Access work, consult `help.qlik.com` directly. The checklist still catalogs the failure classes so reviewers can flag them.

### 7. Cross-Artifact Consistency (4 items)

What fails: expressions referencing fields that don't exist in the final data model, viz specs referencing expressions not in the catalog, scripts calling subroutines not defined in the platform library, and field names that drift across the data model spec, scripts, expression catalog, and viz specs.

Severity: missing-field and missing-expression references are Critical (the artifact will visibly fail). Subroutine and naming drift are Warning.

These checks have no single canonical home because they span artifacts. Verification is done by cross-referencing the artifacts directly. See `qlik-naming-conventions` → cross-layer field mapping for the naming-drift dimension.

### 8. Blocked Dependency Audit (3 items)

What fails: placeholder implementations (for blocked external dependencies) with no `TRACE` warning documenting them, downstream artifacts depending on placeholders without flagging the dependency, and dependency-tracking documents that drift out of sync with actual artifact state.

Severity: Warning across the board. Placeholders don't break code; they make the artifact's completion state opaque to anyone picking it up later.

There is no canonical Qlik home for this category — it's a project-management discipline, not a Qlik mechanic. The patterns are captured here for completeness.

### 9. Data Quality Validation (5 items)

What fails: nulls on key fields, foreign keys in fact tables with no matching primary key (orphaned records), value distributions that suggest bad source data (single value dominating, only one distinct value, unexpected text in numeric fields), row counts that diverge from source-profile expectations, and unexplained orphans in bridge tables.

Severity: nulls on keys are Critical. High null rates on dimensions or measures, referential-integrity failures, and row-count variance are Warning. Distribution oddities are Suggestion.

Canonical home: `data-quality-validator` (post-load and embedded-script query templates). When live data access is available (MCP), use the queries there; when not, treat this category as defer-pending-data.

## Finding Format

Every finding follows this structure. The format is a contract: anyone downstream — a developer applying the fix, an agent verifying the resolution, a status report rolling up by severity — can act on a structured finding without re-reading the source.

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

**ID conventions** used in `references/checklist.md`:

| Prefix | Category |
|---|---|
| `S-` | Script Syntax |
| `P-` | Performance |
| `D-` | Data Model Integrity |
| `N-` | Naming Convention Compliance |
| `E-` | Expression Correctness |
| `SC-` | Security |
| `C-` | Cross-Artifact Consistency |
| `BD-` | Blocked Dependency Audit |
| `DQ-` | Data Quality Validation |

Numbers match the category section (e.g., `S-1.2` is Script Syntax item 1.2, the SQL-constructs check). When writing a finding against an item not pre-numbered (a novel failure pattern), use the prefix and assign the next available number within the category.

## Review Scopes

A QA review is usually scoped to the artifacts on hand. The scope determines which categories apply and what severity bar to apply.

| Scope | Artifacts | Categories Applied | Severity Focus |
|---|---|---|---|
| Data Model | data model specification document | Data Model Integrity, Naming Compliance, Cross-Artifact Consistency (basic) | Critical only |
| Script | load scripts (`.qvs`), optionally with data model spec | Script Syntax, Performance, Data Model Integrity, Naming, Security, Cross-Artifact, Data Quality | Critical + Warning |
| Expression | expression catalog, optionally with variables file and/or data model spec | Expression Correctness, Naming, Cross-Artifact | Critical + Warning |
| Comprehensive | all available artifacts | All 9 categories | Critical + Warning + Suggestion |

**Applicability map** (which categories apply at which scope):

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

The scope/category map is a starting point. Specific projects may broaden or narrow the focus based on the artifact maturity, the deliverable risk, and the time available.

## How to Use This Catalog

1. **Determine review scope** from the artifacts available (or as requested).
2. **Load `references/checklist.md`** for full item detail (verification methods, finding-format templates per item) on the categories in scope.
3. **Iterate through the items** marked for that scope, scanning the artifact for each failure pattern.
4. **Write findings** using the Finding Format above. Use the ID prefix matching the category.
5. **Group findings** by category and severity in the output report.
6. **Surface execution-validation needs** explicitly — many Critical checks (synthetic-key risk, association integrity, data quality validation) require a successful reload to verify. Flag what needs reload-time inspection vs. what was confirmed in static review.

This skill supports the `qa-reviewer` agent's review work but is also usable standalone for ad-hoc reviews, code-review-style passes, and self-checks before sign-off.

## See Also

- **`references/checklist.md`** — Full detailed catalog (items 1.1 through 9.5) with verification methods and finding-format templates for every item.
- **`qlik-naming-conventions`** — Canonical home for naming standards, key conventions, variable naming, cross-layer field mapping.
- **`qlik-load-script`** — Script syntax, QVD operations, null handling, error handling, incremental load patterns. Specifically `references/sql-constructs.md` for the SQL-in-LOAD failures referenced by Section 1.2.
- **`qlik-data-modeling`** — Star schema design, synthetic key prevention, circular reference resolution, grain management. Specifically `references/anti-patterns.md` for the failure modes referenced by Sections 3.1, 3.3, 3.7.
- **`qlik-expressions`** — Expression syntax, set analysis (`references/set-analysis.md`), TOTAL qualifier (`references/total-qualifier.md`), aggregation patterns (`references/aggregation-patterns.md`), variable rules (`references/variable-rules.md`).
- **`qlik-performance`** — Optimization strategies, calculation conditions, memory budgeting, QVD load modes — the canonical home for the performance category.
- **`qlik-visualization`** — Chart selection, layout, filter design — referenced when reviewing visualization specs.
- **`data-quality-validator`** — Post-load and embedded-script validation query templates, used when live data access is available.
