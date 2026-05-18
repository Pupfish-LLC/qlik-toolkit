# pupfish-qlik

> **Make Claude Code fluent in Qlik Sense.** Install once and Claude becomes a Qlik developer you can delegate to — with deep platform knowledge, specialist agents for different tasks, and an automatic syntax check on every script.

## What This Gives You

- **Claude actually understands Qlik.** Without this plugin, Claude drifts into SQL syntax when writing Qlik load scripts, mishandles set analysis, and confuses chart-context behavior with script-context behavior. With it, Claude stops making those mistakes.
- **Specialist agents on demand.** Different jobs need different focus: data architecture, scripting, expressions, visualization, QA review. The right agent shows up automatically based on what you describe — no forced pipeline, no slash commands to memorize.
- **A syntax safety net.** When Claude writes or edits a `.qvs` file, common mistakes are flagged immediately so you catch them before reload, not after.

## Quick Start

### Install from the Claude Code desktop UI

1. In the left sidebar under **Personal plugins**, click the **+** button.
2. Choose **Create plugin → Add marketplace**.
3. In the URL field, enter `Pupfish-LLC/claude-plugins`, then click **Sync**.
4. Once the marketplace is synced, click the **+** button again and choose **Browse plugins**.
5. Find **Pupfish qlik** and install it. The toggle next to the plugin name enables it.

### Install from the command line

1. **Add the Pupfish plugin marketplace** (if you haven't already):

   ```
   /plugin marketplace add Pupfish-LLC/claude-plugins
   ```

2. **Install the plugin:**

   ```
   /plugin install pupfish-qlik@pupfish
   ```

### Then use it

**Just describe what you're doing in Qlik.** Examples:

- *"Help me design a data model for this sales dataset"* → loads `qlik-data-modeling` and offers to invoke the `data-architect` agent.
- *"Review my load script for issues"* → loads `qlik-review-checklist` and invokes `qa-reviewer`.
- *"What's the difference between SET and LET?"* → loads `qlik-load-script`, answers from skill content.
- *"Write a set analysis expression for YoY sales growth"* → loads `qlik-expressions`, returns an expression with correct alternate-state and selection-scope handling.

There are no slash commands to memorize. The skills auto-load when their descriptions match your prompt.

## What's Inside

### Skills (12)

| Skill | What it covers |
|---|---|
| **qlik-load-script** | Script syntax reference, QVD optimization, incremental load patterns (insert-only, SCD2 dual-timestamp), `JOIN`/`KEEP`, `ApplyMap`, `CROSSTABLE`, master calendar, error handling, null handling, diagnostic patterns. |
| **qlik-data-modeling** | Star schema, key resolution (natural / composite / hash / AutoNumber), synthetic-key vs circular-reference distinction, QVD layer architecture, multi-app patterns (single, generator/consumer, four-layer, binary load), source-architecture consumption (dimensional warehouse, OLTP, Data Vault 2.0, pre-joined views, flat files), grain alignment across multiple facts. |
| **qlik-expressions** | Set analysis syntax and modifiers, `TOTAL` qualifier, `Aggr()` patterns, conditional expressions, null handling in expressions, dollar-sign expansion, calculation conditions, common anti-patterns. |
| **qlik-performance** | Memory optimization (field types, dual values, symbolic keys), script load optimization (optimized QVD load rules, redundant disk reads), expression calculation optimization, calculation conditions, data reduction techniques, profiling and diagnostic approaches. |
| **qlik-visualization** | Chart type selection guide, layout patterns, color and formatting, filter design, responsive design, accessibility, reference app reverse-engineering. |
| **qlik-naming-conventions** | Field, variable, table, expression, and file naming standards. Entity-prefix dot notation. Cross-layer field mapping from source through ETL layers to UI display. Reserved words and character restrictions. |
| **qlik-cloud-mcp** | Capability registry for the Qlik Cloud MCP server. Tool-to-pipeline-phase mapping, MCP detection patterns, behavioral gotchas not covered by the tool definitions, multi-step workflows (expression validation, reference app analysis, viz scaffolding, data quality checks). |
| **qlik-review-checklist** | Complete QA checklist used by the `qa-reviewer` agent: data model integrity, naming compliance, script quality, expression correctness, cross-artifact consistency, blocked dependency audit, data quality validation. |
| **data-quality-validator** | Post-load data quality validation query templates: null rate analysis, referential integrity, value distribution, row count validation, orphaned record detection, sparse field identification, duplicate detection. |
| **source-profiler** | Source data profiling: query templates for source schemas, field types, cardinality, null rates, sample values, data quality indicators. Includes source architecture classification (Dimensional Warehouse / OLTP / Data Vault 2.0 / Pre-Joined Views / Flat Files / API) with consumption implications per type. |
| **platform-conventions** | Brownfield platform context template: existing app inventory, shared subroutine catalogs, naming convention maps, data connection standards, QVD storage conventions, organizational coding standards. |
| **qlik-project-scaffold** | Cross-platform Qlik project directory scaffolder. Creates a minimal, unopinionated baseline structure (data-sources, scripts, qvds, documentation, tests) with starter READMEs. Idempotent — safe to re-run. |

### Agents (7)

Think of these as a specialist team you can call on at any point:

- **data-architect** — Designs your data model: star schema, key strategy, QVD layer architecture, ETL boundaries, source-architecture consumption pattern.
- **script-developer** — Writes production Qlik load scripts from a data model specification. Handles incremental loads, master calendar, variables scaffold, error handling, diagnostics.
- **expression-developer** — Authors master measures, master dimensions, calculated dimensions, set-analysis expressions, and variable definitions.
- **viz-architect** — Designs sheet layouts, chart selections, filter panes, navigation flow.
- **qa-reviewer** — Reviews any combination of artifacts (data model, scripts, expressions, full app) against quality standards. Produces structured findings with severity and remediation guidance. Read-only by design.
- **requirements-analyst** — Conducts structured discovery: business requirements, platform context for brownfield projects, user personas, business rules with grain.
- **doc-writer** — Generates project documentation from completed artifacts. Audience-calibrated (technical for developers, plain language for business users).

### Hook

- **PostToolUse on Write/Edit** — Runs `validate-qvs-syntax.sh` on any `.qvs` file written or edited. Scans for SQL constructs in `LOAD` context (`HAVING`, `Count(*)`, `IS NULL`, `BETWEEN`, `IN`, `CASE WHEN`, `LIMIT`, `SELECT DISTINCT`, table aliases), unbalanced control blocks (`IF`/`END IF`, `SUB`/`END SUB`, `FOR`/`NEXT`), and malformed `PurgeChar()` calls (missing second argument). Findings appear before you reload.

## How To Use It (Examples)

Four realistic scenarios:

**1. Ad-hoc syntax help.**
You: *"What's the difference between SET and LET in Qlik?"*
Claude (with `qlik-load-script` auto-loaded): Explains that `SET` preserves the right side as literal text (template), `LET` evaluates immediately. Notes the gotcha that `SET HidePrefix=Chr(37);` assigns the literal string, not `%`.

**2. Data model design.**
You: *"I have a sales fact with customer, product, and store dimensions. Help me model it."*
Claude (with `qlik-data-modeling` auto-loaded): Walks through key resolution strategy, suggests entity-prefix naming, explains synthetic-key prevention. If the design gets complex, Claude may offer to invoke the `data-architect` agent for a structured design pass.

**3. QA review pass.**
You: *"Review this load script for issues."* (pastes script)
Claude (with `qlik-review-checklist` auto-loaded): Invokes the `qa-reviewer` agent. Returns findings classified as Critical / Warning / Suggestion with file locations, what's wrong, impact, and recommended fixes.

**4. Set analysis help.**
You: *"Write a set analysis expression for YoY sales growth."*
Claude (with `qlik-expressions` auto-loaded): Returns `Sum({<[Fiscal Year]={$(=Max([Fiscal Year]))}>} [Order.Amount]) - Sum({<[Fiscal Year]={$(=Max([Fiscal Year])-1)}>} [Order.Amount])` and explains the alternate-state handling.

## What's NOT In This Version

Two planned skills are still in development and will land in a future release:

- **`qlik-security`** — Section Access patterns for row-level and column-level data security. Until it ships, refer to the [Qlik Cloud Section Access docs](https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_Hub/Scripting/Security/manage-security-with-section-access.htm).
- **`qlik-deploy`** — App deployment patterns: data connections, reload tasks, space management, and environment promotion. Until it ships, refer to [Managing apps in Qlik Cloud](https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_Hub/Apps/managing-apps.htm).

## Why No Orchestrator?

The plugin intentionally ships **without a top-level orchestrator agent** that would coordinate the other agents through a fixed pipeline.

Reason: Claude already routes naturally based on what you describe. Each skill's `description` is the trigger. Each agent declares its inputs and capability. An orchestrator would insert a layer between you and Claude's routing — and the cost is flexibility. The intended use cases for this plugin are broad: a quick syntax check, a one-off review, a full project build, a brownfield code audit, a single expression tweak. A fixed pipeline doesn't fit all of those; a fluid prompt-driven flow does.

If a use case emerges where orchestration would clearly help, a slash command can be added in a later release. For now, agents and skills, invoked by intent.

## Roadmap

- [ ] Ship `qlik-security` (Section Access patterns).
- [ ] Ship `qlik-deploy` (app deployment patterns).
- [ ] Optional slash commands for the highest-traffic workflows (driven by user feedback).

## Feedback

Issues, suggestions, and contributions: please open an issue at [github.com/Pupfish-LLC/pupfish-qlik/issues](https://github.com/Pupfish-LLC/pupfish-qlik/issues).

## License

See [LICENSE](LICENSE).

## About

Built by [Pupfish, LLC](https://pupfish.io). The patterns in this plugin are drawn from years of Qlik consulting engagements, distilled into reusable Claude Code skills that any Qlik developer can install and benefit from. All examples in this release use a generic sales / retail domain.
