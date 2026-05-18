# Changelog

All notable changes to the `pupfish-qlik` plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] — 2026-05-18

### Fixed

Resolved an internal contradiction across skills regarding `Count(*)`. The corrected rule is now stated consistently throughout the plugin:

- `Count(*)` is **not valid** in Qlik LOAD / RESIDENT / chart expressions — Qlik's `Count()` function requires an explicit field or expression argument.
- `Count(*)` **is valid** only inside `SQL SELECT` pass-through statements (handed off to the database engine).
- To count NULLs in a field, use `NullCount(field)`. To count all rows in a loaded table, use `NoOfRows('TableName')` after the LOAD.

Specific fixes:

- `skills/data-quality-validator/SKILL.md` — Replaced an invalid `Count(*) - Count([Order.Key])` example with the idiomatic `NullCount([Order.Key])`. Corrected the accompanying note that incorrectly allowed `Count(*)` in RESIDENT LOAD with GROUP BY.
- `skills/qlik-review-checklist/checklist.md` — Replaced the "use `Count(*)` when null rate matters" line with the correct `NullCount(field)` recommendation, plus a flag rule against any occurrence of `Count(*)` in chart or LOAD context.
- `agents/script-developer.md` — Removed the incorrect parenthetical that suggested pure-aggregation `Count(*)` works in RESIDENT LOAD. Expanded the guidance to cover the three valid alternatives (`Count(field)`, `NullCount(field)`, `NoOfRows()`).

## [0.1.0] — 2026-05-18

### Added

- **12 skills** covering Qlik Sense development:
  - `qlik-load-script` — Script syntax, QVD optimization, incremental load patterns, master calendar, error handling, null handling, diagnostic patterns
  - `qlik-data-modeling` — Star schemas, key resolution, synthetic key prevention, multi-app architecture, source-architecture consumption patterns
  - `qlik-expressions` — Set analysis, TOTAL qualifier, `Aggr()`, null handling, dollar-sign expansion, anti-patterns
  - `qlik-performance` — Memory optimization, script load optimization, expression performance, data reduction, profiling
  - `qlik-visualization` — Chart type selection, layout patterns, responsive design, accessibility, reference app patterns
  - `qlik-naming-conventions` — Field, variable, table, expression, and file naming standards with cross-layer field mapping
  - `qlik-cloud-mcp` — Capability registry for the Qlik Cloud MCP server (tool-to-phase mapping, behavioral gotchas, multi-step workflows)
  - `qlik-review-checklist` — QA checklist for data model, naming, script, expression, security gaps, cross-artifact consistency
  - `data-quality-validator` — Post-load data quality validation query patterns
  - `source-profiler` — Source schema profiling, architecture classification (Dimensional Warehouse, OLTP, Data Vault 2.0, flat files)
  - `platform-conventions` — Brownfield platform context template (app inventory, subroutines, naming maps, connections, QVD storage)
  - `qlik-project-scaffold` — Cross-platform Qlik project directory scaffolder (idempotent, unopinionated about workflow)

- **7 specialist agents**:
  - `data-architect` — Designs data architecture from a project spec and source profile
  - `script-developer` — Writes production Qlik load scripts from a data model specification
  - `expression-developer` — Authors master measures, master dimensions, and set-analysis expressions
  - `viz-architect` — Designs sheet layouts, chart selections, filter panes
  - `qa-reviewer` — Reviews any combination of artifacts against quality standards
  - `requirements-analyst` — Conducts discovery: business requirements, platform context for brownfield projects
  - `doc-writer` — Generates project documentation from completed artifacts

- **PostToolUse hook**: `validate-qvs-syntax.sh` — runs against any `.qvs` file written or edited, catching SQL constructs in LOAD context, unbalanced control blocks, and malformed function arguments.

### Notes

- **Initial public release.** All examples use a generic sales / retail example domain (Customer, Order, Product, Region).
- **No rigid orchestration.** The plugin intentionally ships without a top-level orchestrator agent or pipeline. The agents are designed to be invoked individually based on user intent — Claude routes naturally to the right agent based on the user's described task.
- **Two skills deferred** to a future release pending content rewrites against current Qlik documentation:
  - `qlik-security` (Section Access patterns) — original draft contained foundational inaccuracies against Qlik Cloud docs.
  - `qlik-deploy` (deployment patterns) — original draft was missing critical content (data connection name binding, managed-space publish gotchas, Qlik Platform Operations and `qlik-cli` for CI/CD).
- **Companion plugin available:** [`qlik-skill-improvement`](https://github.com/Pupfish-LLC) provides the meta-tooling used to audit, gap-analyze, probe, and edit these skills against authoritative Qlik sources.
