# Changelog

All notable changes to the `qlik-toolkit` plugin (formerly `pupfish-qlik`) are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-05-29

**Production release.** The plugin now teaches Qlik Sense development as a coherent, on-demand collection of agents and skills — agents are thin entry-points, skills are the canonical Qlik teaching surface, and everything follows Anthropic's progressive-disclosure pattern for skill authoring.

### Architecture

- Thin agents + canonical skills. Agent system prompts hold role identity, decision-making, output format, and edge cases; Qlik syntax, anti-pattern catalogs, decision frameworks, and reference tables live in skills.
- Progressive disclosure via `references/`: SKILL.md bodies stay ≤ 500 lines (typical 80–430), with deeper material loaded on demand from `references/` files; templates moved to `assets/`; executable scaffolders to `scripts/`.
- All 7 agents brought within Anthropic's recommended size range (94–142 lines).

### Content consolidation

One canonical home per Qlik topic — cross-skill duplication eliminated:

- **Naming** → `qlik-naming-conventions`
- **SQL constructs not in Qlik** → `qlik-load-script/references/sql-constructs.md`
- **Null handling (script layer)** → `qlik-load-script/references/null-handling.md`
- **Null handling (expression layer)** → `qlik-expressions/SKILL.md` §9
- **QVD operations (mechanics)** → `qlik-load-script/references/qvd-operations.md`
- **Performance thresholds + QVD decisions** → `qlik-performance`
- **Data modeling anti-patterns (synthetic keys, circular references, QUALIFY discipline)** → `qlik-data-modeling/references/anti-patterns.md`
- **Set analysis** → `qlik-expressions/references/set-analysis.md`
- **TOTAL qualifier, Aggr patterns, variable rules** → `qlik-expressions/references/{total-qualifier,aggregation-patterns,variable-rules}.md`
- **Visualization** → `qlik-visualization`
- **QA checklist** → `qlik-review-checklist`

### Skill changes

- Renamed `platform-conventions` → `qlik-platform-discovery`. Reframed from a per-agent ingestion procedure into standalone brownfield-pattern teaching (subroutine identification, naming-variation catalog, QVD storage patterns). Template moved to `references/`.
- `qlik-project-scaffold` slimmed from 155 → 79 lines; five README templates moved to `assets/`; PowerShell + Bash scaffolders extracted to `scripts/` (idempotent, tested on Windows + POSIX).
- `qlik-review-checklist` rewritten as standalone QA knowledge — failure-class catalog, severity model, finding format — rather than a workflow procedure tied to a specific agent. Detailed checklist moved to `references/checklist.md`.
- W01 structural moves into `references/` (progressive-disclosure cleanup):
  - `qlik-data-modeling/{star-schema-patterns,multi-app-architecture,source-consumption-patterns}.md`
  - `qlik-load-script/{incremental-load-patterns,diagnostic-patterns}.md`
  - `qlik-visualization/reference-app-patterns.md`

### Agent changes

- All 7 agents trimmed to target line counts (viz-architect 94, doc-writer 95, expression-developer 96, data-architect 109, script-developer 123, requirements-analyst 138, qa-reviewer 142).
- Every agent has an explicit `## When to invoke` body section.
- 6 agents upgraded to the Opus model (requirements-analyst, data-architect, script-developer, expression-developer, viz-architect, qa-reviewer); doc-writer remains on Sonnet.
- Frontmatter descriptions rewritten in third-person WHAT/WHEN format per Anthropic skill-authoring guidance, wrapped in double quotes for consistency.

### Accuracy fixes

Seven Qlik behavior claims corrected against tier-1 sources during the cleanup:

1. **`Count(1)` "fragile during incremental loads"** — claim removed. Tier-1 documentation does not characterize `Count(1)` this way; the prior assertion was unsourced. (T02)
2. **`NULL = 0` evaluation** — corrected. The comparison returns False, not NULL, per Qlik's three-valued-logic handling for equality against a literal. (T03)
3. **Set analysis exclusion syntax** — replaced a fabricated `-Returns` example with the documented forms (`-=` implicit set operator and `{1-<…>}` set-difference). (T07)
4. **Rolling 12 months YYYYMM arithmetic** — replaced a broken `(Year*100 + Month) - 11` expression (which produces non-existent months like 202113) with `AddMonths(…)`-based form and a `Year*12 + Month` linear-index alternative. (T07)
5. **`LET` "cached value" terminology** — rewritten. `LET` evaluates the right side at assignment time and stores the result; "cached" implied lazy/recomputable semantics it doesn't have. (T08)
6. **Responsive grid "24 columns"** — debunked. Qlik's documented responsive behavior is a single 480-pixel small-screen threshold plus 300–4000px custom sheet sizing, not a column-grid system. (T09)
7. **Filter pane mobile "drawer" behavior** — corrected. Documented behavior is dimension shrink + overflow chevron dropdown, not a slide-in drawer. (T09)

### Removed

- Orchestration vocabulary across all published surfaces: `phase 1/2/3`, `pipeline phase`, `orchestrator`, `orchestration`.
- Agent-to-agent handoff language (`hand off to the X agent`, `consumed by the X agent`, `delegated to the X agent`).
- Workflow-phase framing in skill descriptions (`Use this skill during the X phase`, `Use this skill when [phase/role]`).
- Legacy root-level reference files now resident in `references/` per progressive disclosure.

### Internal

- Anthropic-aligned progressive disclosure throughout: SKILL.md bodies ≤ 500 lines (1,500–2,000 words target), deeper material in `references/`, templates in `assets/`, scripts in `scripts/`.
- Every Qlik behavior claim newly written or substantially reworded during the cleanup was validated against `qlik-source-registry` tier sources where applicable; per-cluster validation evidence retained in cluster summaries.
- Cleanup planning artifacts (`cleanup-plan/`, `pending-traps.md`) were `.gitignore`d throughout the cleanup and never shipped.

## [0.4.0] — 2026-05-27

### Added

- **`qlik-visualization/SKILL.md` §8 (NEW: Dashboard Bundle Controls):** Documented the Variable Input control's Dynamic values mode. The parameter parses a pipe-delimited string (`value1|value2|...`) or value-label form (`value~label|value~label|...`), NOT a field enumeration. A bare field reference (`=[Table].[Field]`) collapses to one scalar — the dropdown breaks. Corrective pattern: materialize the pipe string in the load script (Concat-and-Peek), reference the resulting variable as `='$(vPipe)'`.
- **`qlik-visualization/references/variable-input-control.md` (NEW):** Full walkthrough of the Variable Input pipe pattern — load-script Concat-and-Peek build, control configuration, value-only vs value-label form, chart-side double-dollar expansion (`$($(vVar))`) when the picker writes a variable name, and the slower inline-Concat alternative.
- **`qlik-load-script/SKILL.md` §7 (Data-Driven Patterns):** New "Concat-and-Peek for UI-variable build" subsection. General script-side technique for materializing a delimited string into a variable; cross-references the qlik-visualization walkthrough for UI consumption.
- **`qlik-load-script/SKILL.md` §14 (NoConcatenate and Auto-Concatenation):** Added an INLINE-specific paragraph and example. The same auto-concatenation rule that applies to RESIDENT also applies to LOAD INLINE — two INLINE blocks with matching column structures silently merge, the second table name is lost, and a later `RESIDENT [SecondTable]` fails with "table not found" (the typical symptom that surfaces the trap).

### Changed

- **TRACE semicolon rule reframed in `qlik-load-script/SKILL.md` §13 and `qlik-load-script/diagnostic-patterns.md`:** The v0.3.1 framing ("no semicolons allowed inside a TRACE message") was too absolute. Restated as the parser-level rule (`;` terminates outside any quoted string; TRACE accepts an unquoted argument by default), with two safe options now documented: (a) use commas, periods, or dashes as in-text separators (the prior advice), and (b) wrap the entire trace text in single quotes so the `;` sits inside a string literal. Added "treat TRACE text the way you'd treat any other Qlik string argument — when in doubt, quote it" as a closing note.

## [0.3.1] — 2026-05-18

### Fixed

- **`data-quality-validator/validation-queries.md` §3:** Removed an embedded semicolon inside a TRACE message (`TRACE [WARNING] Customer.Region cardinality is $(vRegionCount); expected 4-6 unique values;`). The first `;` would have terminated the TRACE early and made the trailing text parse as an invalid statement, breaking the reload. Replaced with a comma.

### Added

- **TRACE semicolon rule documented across the plugin:**
  - `qlik-load-script/SKILL.md` §13 (Error Handling and Logging): added explicit rule that semicolons inside the TRACE message are not allowed; explained why (TRACE has no quoted argument, the first `;` terminates the statement); examples of right/wrong patterns.
  - `qlik-load-script/diagnostic-patterns.md` (TRACE Statement Templates): added the same rule with right/wrong examples at the top of the TRACE section.
  - `qlik-review-checklist/checklist.md` §1: added item 1.7 "Semicolons inside TRACE Messages" as a Critical finding with a structured finding format. Script Syntax category count updated from 6 to 7 items.
  - `hooks/validate-qvs-syntax.sh`: added check #9 to flag TRACE lines with more than one `;`. Now catches this pre-reload during Write/Edit.

## [0.3.0] — 2026-05-18

### Changed

Comprehensive retune of all 7 agents (and a small pass on 3 skill files) to fit the ad-hoc invocation model. Prior wording assumed a rigid sequenced workflow with specific upstream artifacts at each step; this release removes that scaffolding so each agent stands alone and adapts to whatever the user has shared.

Per-agent changes (consistent pattern across all seven):

- Replaced rigid "Inputs" sections (which named specific upstream artifacts like "Project Specification," "Data Model Specification," "Platform Context Document") with adaptive "Working from what you have" sections. The agents now expect the user to share whatever context exists — a description, a screenshot, named files, a paste — and ask for what they need rather than demanding a specific artifact format.
- Dropped "Out of scope" sections that named other agents by role ("writing scripts is the script-developer's role"). Replaced with topic-based scope statements.
- Reframed runbook-style "Working Procedure" sections as adaptive "Approach" sections, with steps roughly sequenced but skipped or adapted to the actual ask.
- Dropped formal transfer-of-control sections that described passing artifacts to a coordinator. Replaced with brief "After producing X" guidance on what to summarize.
- Reframed iterative-feedback sections to describe how the agent handles follow-up requests in conversation (rather than coordinator callbacks).
- Removed artifact-version metadata templates (`**Artifact:** ... **Version:** 1.0 **Status:** Draft **Inputs:** ...`) from output specifications. The substance (section structures, format guidance) is preserved.
- Output paths reframed as user-controlled with a sensible default, not as hardcoded conventions.

Skill changes:

- `qlik-review-checklist/checklist.md` §8: dropped sequenced-workflow-state framing.
- `platform-conventions/platform-context-template.md`: dropped references to a specific `inputs/` directory structure and the artifact-transfer framing around platform discovery.

### Why

The agents were originally written for the `qlik-agents` plugin, which used a rigid nine-step sequenced workflow driven by a top-level coordinator agent. When they were extracted to `qlik-toolkit` (intentionally ad-hoc, no top-level coordinator), the agents themselves weren't retuned. Heavy sequenced-workflow assumptions in the agent prompts created friction in ad-hoc use — agents would demand artifacts that didn't exist, or describe transferring artifacts to other agents that may not even be invoked. This release brings the agent personalities in line with the toolkit's actual usage model.

No changes to Qlik domain knowledge in the skills, no changes to the validation hook. Functional content is unchanged.

## [0.2.0] — 2026-05-18

### Changed

- **Plugin renamed from `pupfish-qlik` to `qlik-toolkit`.** The repository now lives at https://github.com/Pupfish-LLC/qlik-toolkit (GitHub auto-redirects the old URL).
- **Author display rebranded from "Pupfish, LLC" to "Pupfish Analytics"** in user-facing surfaces (plugin manifest, README, marketplace listings). The legal entity (LICENSE / NOTICE) is unchanged.

No functional changes to skills, agents, or the validation hook. Plugin content is byte-identical to 0.1.2.

### Migration

If you have `pupfish-qlik` installed:
1. Uninstall it: `/plugin uninstall pupfish-qlik` (or remove via the GUI).
2. Refresh the marketplace, then install the renamed plugin: `/plugin install qlik-toolkit@pupfish`.

## [0.1.2] — 2026-05-18

### Fixed

Comprehensive accuracy pass against current help.qlik.com documentation, addressing ~30 inaccurate claims that the original audit identified but 0.1.0 / 0.1.1 shipped with. Anyone running 0.1.0 or 0.1.1 should upgrade.

Every claim corrected in this release was re-verified against the canonical Qlik help page (or vendor docs for SQL items), and the citation is recorded in the per-skill audit reports under `staging/<skill>/audit-report.md`. Highlights:

- **qlik-performance**
  - Corrected QVD optimized-read rules. Per Qlik help, only three operations disable optimization: transformations on loaded fields, WHERE clauses that force record unpacking, and `Map()` applied to a loaded field. Field renaming via `AS` and field reordering are explicitly allowed and do NOT break optimized read. (Source: help.qlik.com `work-with-QVD-files.htm`.)
  - Removed the fictional set-analysis `with` operator. Set modifiers are comma-separated inside `<…>`; the legitimate set operators (`+`, `-`, `*`, `/`) combine whole set expressions.
  - Corrected `Hash128()` description: returns a 22-character string per docs, not a numeric. For memory-saving integer keys, use `AutoNumber()` or `AutoNumberHash128()`.
  - Renamed "Performance Profiler" to its actual Qlik Cloud name **App Performance Evaluation** (sheet/object-level scope, not expression-level).
  - Removed fictional `EXISTS(field, $1)` syntax. Documented signature is `Exists(field_name [, expr])`.
  - Softened the `Count(DISTINCT)` "expensive" claim. The Qlik help page makes no performance claim either direction; the prior "expensive" assertion was sourced only to a non-fetchable community blog post.
  - Reframed the field memory-cost section around the documented symbol-table / bit-stuffed-pointer model; removed unsourced specific byte counts.
- **qlik-expressions**
  - Corrected `$1` description: it is **previous selection history** (back-button stack), not an alternate-state reference. Alternate states are referenced by bare name without `$` prefix. Added `$_N` forward history.
  - Fixed `Alt()` claim: per docs, `Alt()` returns the first parameter with a valid **numeric** representation. Examples like `Alt([Customer.Name], 'Unknown')` always fall through to the default. The proper text/general null-coalescer is `Coalesce()` — now documented with examples.
  - Reversed the flag-multiplication-vs-set-analysis performance claim for large datasets, per Henric Cronström's Qlik Design Blog testing: set analysis is faster on large fact tables.
  - Added documentation for set-analysis quoting rules (single quotes = literal/case-sensitive match; double quotes = case-insensitive search) and implicit set operators (`+=`, `-=`, `*=`, `/=`).
  - Replaced a non-illustrative anti-pattern fix example with a clearer "operator without left-side set identifier" case.
  - Fixed search-string examples to use the required `<FieldName={"=..."}>` field-scoping form.
- **qlik-cloud-mcp**
  - Added 8 missing tools to the registry: bookmark tools (`list_bookmarks`, `create_bookmark`, `select_bookmark`, `delete_bookmark`) and master-item mutation tools (`update_dimension`, `update_measure`, `delete_dimension`, `delete_measure`).
  - Fixed the `search_field_values` Section 5.4 workflow example: `fieldName` is required per the documented signature. The "cross-field search" via omitting `fieldName` is not documented and was removed.
  - Rewrote the master-items restriction to match official MCP docs: "You can only update and delete master items created using Qlik MCP tools." Same applies to bookmarks. Separated this MCP-only mutation rule from the (independent) published-app platform rule.
  - Cleaned up a stale `spaceId` claim on `qlik_search` in behavioral-notes (the tool searches apps/datasets/data products/glossaries, not spaces).
- **qlik-visualization**
  - Replaced fabricated tiered breakpoints (1200px / 768px / "Desktop/Tablet/Mobile") with the single documented threshold (480-pixel small-screen mode) and the 300-4000px custom sheet-size range.
  - Corrected menu paths to **Sheet properties → Sheet size (Responsive / Custom)**. Removed references to the non-existent "Responsive Preview Mode" feature.
  - Standardized terminology to **Alternate states** (Qlik's actual term), with correct location: Master items → Alternate states, applied per visualization via Appearance → Alternate states.
  - Corrected the KPI trending claim: the standard KPI supports conditional symbols (check/caution/X) via range limits, not "up/down arrows." Trend arrows lived in the Multi-KPI bundle, which is deprecated (no new instances since April 5, 2025; full removal May 2027). Recommendation now: place a separate spark/trend chart next to the KPI.
  - Corrected the filter-pane "hamburger menu" claim. Documented behavior: pane shrinks dimensions, then uses a dropdown chevron for overflow.
  - Annotated several practitioner heuristics (WCAG 4.5:1 contrast, viridis/cividis palette names, 8% colorblindness statistic, cardinality thresholds, 15-column table limit, font-pt sizes) so they aren't presented as Qlik-specific.
- **source-profiler**
  - Fixed SQL Server `STRING_AGG DISTINCT` syntax error (SQL Server doesn't allow `DISTINCT` inside `STRING_AGG`). Split into stats query plus a `DISTINCT TOP N` subquery feeding `STRING_AGG`.
  - Fixed PostgreSQL `LIMIT 5` on a single-row aggregate (no-op). Moved `LIMIT` into a `DISTINCT` subquery that feeds `STRING_AGG`.
  - Fixed MySQL `LIMIT 5` on a single-row aggregate (same issue). Used a subquery; added a note about the `group_concat_max_len` system variable for result truncation.
  - Corrected SCD Type 2 definition in `profile-template.md` (history preserved by inserting a new row; the prior "attributes overwritten" wording was SCD Type 1).
- **data-quality-validator/validation-queries.md**
  - Fixed Qlik LIKE pattern that used regex-style character classes `[a-zA-Z]` (not supported — Qlik LIKE only uses `*` and `?`). Replaced with `NOT IsNum(...) AND Len(Trim(...)) > 0`.
  - Fixed `Concat()` misuse for per-row hashing — `Concat()` is a string-aggregation function over rows; use the `&` operator for per-row.
  - Fixed `UNION ALL` after a terminating semicolon (the `;` ended the statement, leaving `UNION ALL` as a syntax error).
  - Labeled the `SELECT TOP` example as SQL Server-only and added a PostgreSQL / MySQL `LIMIT` variant.
  - Moved a `WHERE` clause that referenced `COUNT()` into `HAVING` (aggregates can't appear in `WHERE`).
- **qlik-review-checklist**
  - Reconciled item counts: `Script Syntax` now correctly stated as 6 items (was claimed as 9); `Expression Correctness` header now correctly stated as 7 items (was claimed as 6).
  - Reordered item 5.7 (Structurally Invalid Aggregation) to its proper numerical position after 5.6.
  - Reconciled the §8 (Blocked Dependency Audit) applicability header to match the per-item declarations: Script (light) / Expression (light) / Comprehensive.
- **qlik-naming-conventions**
  - Corrected the Mapping RENAME warning: `Rename Fields` is atomic across the data model. The real reason to avoid renaming keys at this layer is semantic — key standardization belongs at the Transform layer.
  - Corrected the `$(v.MyVar)` description: dots in variable names parse via standard dollar-sign expansion (the dot is just a character), not "property access." The discouragement is stylistic, not a parser issue.
  - Added missing reserved characters to the character-restriction table: `:`, `(`, `)`, `` ` `` (backtick), `´` (acute accent) — all per the Qlik visualizations/fields naming guidelines page.
  - Expanded the system fields list from 2 (`$Table`, `$Field`) to the documented 5 (`$Table`, `$Field`, `$Fields`, `$FieldNo`, `$Rows`).

### Items shipped with softened (rather than fully verified) language

Two items in `qlik-performance` could not be reverified against fetchable primary sources in this pass and were softened rather than asserted in the opposite direction:

1. **`Count(DISTINCT)` performance.** The Qlik help page on `Count()` makes no performance claim. Henric Cronström's Qlik Design Blog post that prior audits cited could not be retrieved verbatim. The skill now states neutrally that the docs do not characterize it as slow, and points readers to actual profiling (App Performance Evaluation).
2. **Field-type byte sizes.** Qlik's official documentation does not publish specific byte sizes per field type. The skill no longer makes unsourced byte claims; it instead reframes the discussion around the documented symbol-table / bit-stuffed-pointer model.

If you can locate fetchable Tier-1 sources for either claim, please open an issue.

### Process note

The original audit pipeline reasoned circularly in places ("the skill uses it, so it must work") and missed SQL-influenced misconceptions in Qlik LOAD context. This release was produced by re-verifying every flagged finding directly against current `help.qlik.com` function-signature pages, with cross-vendor docs (Microsoft Learn, postgresql.org, dev.mysql.com) for the SQL items.

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
- **No fixed workflow.** The plugin intentionally ships without a top-level coordinator agent or fixed sequence. The agents are designed to be invoked individually based on user intent — Claude routes naturally to the right agent based on the user's described task.
- **Two skills deferred** to a future release pending content rewrites against current Qlik documentation:
  - `qlik-security` (Section Access patterns) — original draft contained foundational inaccuracies against Qlik Cloud docs.
  - `qlik-deploy` (deployment patterns) — original draft was missing critical content (data connection name binding, managed-space publish gotchas, Qlik Platform Operations and `qlik-cli` for CI/CD).
- **Companion plugin available:** [`qlik-skill-improvement`](https://github.com/Pupfish-LLC) provides the meta-tooling used to audit, gap-analyze, probe, and edit these skills against authoritative Qlik sources.
