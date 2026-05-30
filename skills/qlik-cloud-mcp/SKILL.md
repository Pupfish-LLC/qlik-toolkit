---
name: qlik-cloud-mcp
description: "Capability registry for the Qlik Cloud MCP server: maps MCP tools to development tasks, provides MCP detection patterns, documents behavioral gotchas not covered by tool definitions, and defines multi-step workflows for expression validation, reference app analysis, visualization scaffolding, and data quality checks against a live tenant. The MCP tool definitions themselves document parameters and response structure; this skill covers framework integration, sequencing, and pitfalls discovered through live testing. Load when interacting with a live Qlik Cloud tenant via MCP, validating an expression against real data, analyzing a reference app, or running post-load data quality checks."
user-invocable: false
---

# Qlik Cloud MCP — Capability Registry

## What This Skill Covers (and What It Doesn't)

The MCP tool definitions (visible to every agent at invocation time) already document each tool's parameters, response structures, usage examples, and basic notes. This skill does NOT repeat that information.

This skill covers:

- **MCP detection** — how agents determine MCP availability and branch
- **Tool-to-task mapping** — which tools are relevant for which development task
- **Behavioral gotchas** — issues discovered through live testing that go beyond the tool definitions (see `references/behavioral-notes.md` for the full list)
- **Workflow patterns** — multi-step tool call sequences for common operations
- **Framing** — what the MCP server can and cannot do, to prevent incorrect assumptions

## What the Qlik Cloud MCP Server IS and IS NOT

**IS:** The Qlik Cloud platform API exposed through MCP. It operates on data and objects already in Qlik Cloud: apps, datasets in the catalog, master items, sheets, glossaries, data products, and lineage metadata.

**IS NOT:** A direct connection to upstream source databases. It cannot run SQL queries against SQL Server, PostgreSQL, or any source system. Source database profiling (Path A in the source-profiler skill) requires separate database MCP connections. If those aren't available, the source-profiler's manual template path (Path B) applies.

**The practical distinction:** When a workflow says "MCP available" for source profiling, it means a database MCP connection, not the Qlik Cloud MCP server. The Qlik Cloud MCP server enables a different set of capabilities: inspecting what's already loaded in Qlik apps, validating expressions against live data, scaffolding visualizations, profiling Qlik-managed datasets (QVDs, cloud data files), and tracing lineage.

## MCP Detection

Before using any tool in this registry, agents must determine whether the Qlik Cloud MCP tools are available in the current session. Tools are prefixed with `qlik_`.

```
IF qlik_* tools are present:
    Qlik Cloud MCP is live → use MCP-enhanced workflows
ELSE:
    Qlik Cloud MCP unavailable → use manual fallback workflows
    Log "Qlik Cloud MCP unavailable" for the session's context
```

MCP availability can change between sessions. Always check, never assume.

## Tool-to-Task Mapping

This table maps every MCP tool to the development task where it's useful. Tools not listed here are governance tools documented in Section 6.

Task abbreviations: **REF** = reference app analysis · **PROF** = source / dataset profiling · **MOD** = data model design · **SCRIPT** = script-time validation · **EXPR** = expression authoring/validation · **VIZ** = visualization scaffolding · **QA** = QA / data quality review.

| Tool | REF | PROF | MOD | SCRIPT | EXPR | VIZ | QA |
|---|---|---|---|---|---|---|---|
| `qlik_describe_app` | ● | | | | | | |
| `qlik_get_fields` | ● | | ● | ● | | | ● |
| `qlik_get_field_values` | | ● | ● | | ● | | ● |
| `qlik_search_field_values` | ● | | ● | | ● | | ● |
| `qlik_list_sheets` | ● | | | | | ● | |
| `qlik_get_sheet_details` | ● | | | | | ● | ● |
| `qlik_list_dimensions` | ● | | | | ● | ● | |
| `qlik_list_measures` | ● | | | | ● | ● | |
| `qlik_create_data_object` | | | | ● | ● | | ● |
| `qlik_get_chart_data` | | | | | ● | | ● |
| `qlik_get_chart_info` | ● | | | | | | ● |
| `qlik_select_values` | | | | | ● | | ● |
| `qlik_clear_selections` | | | | | ● | | ● |
| `qlik_get_current_selections` | | | | | ● | | ● |
| `qlik_list_bookmarks` | ● | | | | ● | | |
| `qlik_create_bookmark` | | | | | ● | | |
| `qlik_select_bookmark` | ● | | | | ● | | |
| `qlik_delete_bookmark` | | | | | ● | | |
| `qlik_create_sheet` | | | | | | ● | |
| `qlik_add_chart` | | | | | | ● | |
| `qlik_add_filter` | | | | | | ● | |
| `qlik_create_dimension` | | | | | | ● | |
| `qlik_create_measure` | | | | | ● | ● | |
| `qlik_update_dimension` | | | | | | ● | |
| `qlik_update_measure` | | | | | ● | ● | |
| `qlik_delete_dimension` | | | | | | ● | |
| `qlik_delete_measure` | | | | | | ● | |
| `qlik_search` | ● | ● | | | | | |
| `qlik_get_dataset` | | ● | | | | | |
| `qlik_get_dataset_schema` | | ● | | | | | |
| `qlik_get_dataset_sample` | | ● | | | | | ● |
| `qlik_get_dataset_profile` | | ● | | | | | ● |
| `qlik_get_dataset_freshness` | | ● | | | | | ● |
| `qlik_get_dataset_trust_score` | | | | | | | ● |
| `qlik_get_lineage` | ● | ● | | | | | |

**Reading the table:** ● means the tool has a defined use in that task. Consult the relevant workflow pattern (Section 5) for the sequencing.

## Key Behavioral Notes

These are gotchas discovered through live testing that are NOT documented in the tool definitions. For the complete per-tool list, read `references/behavioral-notes.md`.

**Silent failures are the biggest risk.** Several tools return null/zero instead of errors when given invalid input:
- `qlik_create_data_object`: Referencing a non-existent field returns null/0, not an error. Always verify field names with `qlik_get_fields` first.
- `qlik_select_values`: Selecting a value that doesn't exist in the field produces an empty selection silently. The returned selection list is the ground truth -- if the field doesn't appear in it, the selection failed.
- `qlik_create_measure` / `qlik_add_chart`: Invalid expressions succeed at creation time but fail at render time. Always validate expressions with `qlik_create_data_object` before creating permanent objects.

**Selection state is persistent and cumulative.** `qlik_select_values` filters the entire session. Every subsequent `qlik_create_data_object`, `qlik_get_field_values`, and `qlik_get_chart_data` call reflects active selections. Always call `qlik_clear_selections` after validation runs. Some app-level default selections (script-embedded, Section Access, default bookmarks) cannot be cleared via MCP. Always call `qlik_get_current_selections` before profiling or validation work and document any active selections. When profiling, if selections cannot be cleared, consider using `{1}` set analysis to ensure data is profiled across all values, not only those currently selected.

**Visualization creation has no layout control.** `qlik_create_sheet`, `qlik_add_chart`, and `qlik_add_filter` create objects but provide zero control over grid positioning, sizing, visual formatting, colors, number formats, or conditional formatting. Objects are appended sequentially. The manual build checklist remains essential for final layout work.

**MCP-only mutation rule (master items and bookmarks).** The MCP server enforces a hard restriction documented as: "You can only update and delete master items created using Qlik MCP tools." In practice, `qlik_update_dimension` / `qlik_update_measure` / `qlik_delete_dimension` / `qlik_delete_measure` will only act on items that this MCP session (or a prior MCP session) created. Pre-existing user-created master items in the app are read-only through MCP. The same restriction applies to bookmarks: "You can only delete bookmarks created using Qlik MCP tools." Separately, the standard Qlik Sense platform rule still applies: in published apps (managed spaces) master-item changes must be made in the source app and re-published. If a master measure is renamed or deleted, expressions that reference it by name return NULL silently rather than raising an error.

**Hypercube cell limit.** `qlik_create_data_object` and `qlik_get_chart_data` are subject to a 10,000 cells per request limit (dimensions × measures × rows). For large result sets, use pagination (offset/limit) and keep dimension cardinality bounded with sort + limit settings.

**Lineage is one level per call.** `qlik_get_lineage` returns only immediate upstream dependencies. To trace a full pipeline (Source → Extract → QVD → Transform → App), call recursively on each upstream node. QRI format for apps: `qri:app:sense://[appId]`. Get dataset QRIs from `qlik_get_dataset` response. Lineage stops at the tenant boundary: external sources appear as a terminal node, and `LIB CONNECT` chains to ODBC/REST sources end at the connection name, not the source table — source-system-side lineage is not retrievable via MCP.

**Trust scores are often absent.** `qlik_get_dataset_trust_score` returns an error (not null) when no trust score exists. Handle this gracefully -- most datasets won't have one unless explicitly assessed.

## Workflow Patterns

These are the multi-step tool call sequences agents should follow. Each pattern lists the tools in order with the reasoning for each step.

### 5.1 Reference App Analysis

Use when analyzing an existing app to extract patterns for replication.

```
1. qlik_describe_app(appId)
   → App overview, field count, metadata. First call for any app.

2. qlik_get_fields(appId)
   → Full field inventory. Note $key, $date, $numeric tags for
   type classification and association detection.

3. qlik_list_sheets(appId)
   → Sheet inventory. Get IDs for step 4.
   ⚠ Do NOT rely on the cells array here -- it's truncated.

4. For each sheet: qlik_get_sheet_details(appId, sheetId)
   → Complete object list per sheet. Extract chart types,
   dimension/measure assignments.

5. qlik_list_dimensions(appId) + qlik_list_measures(appId)
   → Master item inventory with definitions and expressions.

6. qlik_get_lineage(qri:app:sense://[appId])
   → Trace upstream pipeline. Recurse on each upstream node
   for full lineage chain.
```

MCP cannot reveal table membership: `qlik_get_fields` returns field-level tags but no table assignment. To reconstruct the table-association map, combine the `$key`-tagged fields from `qlik_get_fields` with the app's load script (or use `qlik_get_lineage` to trace back to a QVD dataset and read its schema). Fields sharing the same `$key` value across tables indicate the associations Qlik built in memory.

### 5.2 Expression Validation

Highest-value MCP integration. Validates expressions from the expression catalog against loaded data.

```
1. qlik_clear_selections(appId)
   → Ensure clean state. Verify with qlik_get_current_selections.

2. qlik_get_fields(appId)
   → Build field name lookup. Every field reference in every
   expression must match exactly (case-sensitive).

3. For each expression in the catalog:
   a. qlik_create_data_object with the expression and a relevant dimension
   b. Check result:
      - Non-null → expression evaluates ✓
      - Null/0 → could be valid (no matching data) or invalid
        (field typo, syntax error). Cross-check with
        qlik_get_field_values to confirm data exists.

4. For set analysis expressions, test with known-good values:
   - Sum({<Year={2024}>} [Amount]) with a year known to have data
   - Verify the filter produces expected narrowing

5. For comparative expressions (YoY, variance):
   a. qlik_select_values to set a known context
   b. Evaluate the expression
   c. qlik_clear_selections immediately after

6. Produce validation summary:
   | Expression | Expected | Actual | Status | Notes |
   |---|---|---|---|---|
   | vRevenue | Numeric > 0 | 1,234,567 | ✓ Pass | |
   | vMargin | 0-100% | null | ⚠ Investigate | Check field name |
```

### 5.3 Visualization Scaffolding

Creates the skeleton of sheets and objects. Manual work is still required for layout and formatting.

```
1. Create master dimensions:
   For each dimension in master item definitions:
     qlik_create_dimension(appId, name, dim, description)
     → Record returned libraryId

2. Create master measures:
   For each measure in expression catalog:
     qlik_create_measure(appId, name, expr, description)
     → Record returned libraryId
   ⚠ Validate expressions with qlik_create_data_object BEFORE this step.
   Invalid expressions succeed here but fail at render.

3. Create sheets:
   For each sheet in viz specifications:
     qlik_create_sheet(appId, title, description)
     → Record returned sheetId

4. Add filter panes, then charts:
   For each sheet:
     qlik_add_filter(appId, sheetId, title, fields)
     qlik_add_chart(appId, sheetId, chartType, title,
       dimensions=[{libraryId: dimId}],
       measures=[{libraryId: measureId}])

5. Document what requires manual completion:
   - Grid positioning and object sizing
   - Visual formatting (colors, fonts, number formats)
   - Conditional formatting and calculation conditions
   - Responsive behavior adjustments
```

### 5.4 Data Quality Validation

Validates data quality through MCP as part of comprehensive QA.

```
1. qlik_clear_selections(appId)

2. Null rate checks per key field:
   qlik_create_data_object(measures=[
     {expression: "Count([Field])", label: "Non-Null"},
     {expression: "NullCount([Field])", label: "Nulls"}
   ], dimensions=[])

3. Uniqueness checks on key fields:
   qlik_create_data_object(measures=[
     {expression: "Count([KeyField])", label: "Total"},
     {expression: "Count(DISTINCT [KeyField])", label: "Distinct"}
   ], dimensions=[])
   → Total != Distinct means duplicates. Critical finding.

4. Encoded null scan (iterate per field):
   For each candidate field in the field list:
     qlik_search_field_values(fieldName=field, searchTerms=["N/A", "NULL", "TBD",
       "-", "Unknown", "NONE", "n/a"])
   → Surfaces fields where common null encodings have leaked in as values.
   Note: `fieldName` is required per the official tool signature
   (qlik_search_field_values(fieldName, searchTerms)); there is no documented
   cross-field-search mode.

5. For Qlik-managed datasets, augment with catalog tools:
   qlik_get_dataset_profile(datasetId) → pre-computed statistics
   qlik_get_dataset_freshness(datasetId) → data currency
   qlik_get_dataset_trust_score(datasetId) → may return error (handle gracefully)
```

### 5.5 Post-Reload Spot Checks

Quick validation that data loaded correctly after a Qlik reload.

```
1. qlik_get_fields(appId)
   → Verify expected fields exist. Check $numeric/$text/$date tags
   match expected types.

2. Row count checks:
   qlik_create_data_object(measures=[
     {expression: "Count([Table.KeyField])", label: "Rows"}
   ], dimensions=[])
   → Compare against expected row counts from source profiling.

3. Spot-check field values:
   qlik_get_field_values(appId, fieldName, limit=20)
   → Verify sample values look reasonable.
```

## Governance Tools

The MCP server includes tools for Qlik Cloud governance features (business glossaries and data products). These aren't tied to any specific development task but provide value for organizations using Qlik's governance capabilities.

**Business Glossary tools** (`qlik_create_glossary`, `qlik_create_glossary_term`, `qlik_create_glossary_category`, `qlik_search_glossary_terms`, `qlik_get_glossary_term`, `qlik_update_glossary_term`, `qlik_update_term_status`, `qlik_delete_glossary_term`, `qlik_get_glossary_categories`, `qlik_get_glossary_term_links`, `qlik_create_glossary_term_links`, `qlik_get_full_glossary_export`): Create and manage governed business term definitions. Terms can be linked to apps, datasets, fields, master dimensions, and master measures via `qlik_create_glossary_term_links`. Term status follows a `draft → verified → deprecated` lifecycle where only stewards can verify or modify verified terms. Linking glossary terms to master items brings business context into the app for end users. As a best practice, place glossaries in a shared space where all tenant users have Can view access.

**Data Product tools** (`qlik_create_data_product`, `qlik_get_data_product`, `qlik_get_data_product_documentation`, `qlik_update_data_product`, `qlik_update_data_product_space`, `qlik_update_activate_data_product`, `qlik_update_deactivate_data_product`, `qlik_delete_data_product`): Curated, governed bundles of datasets. Support a `draft → active → deactivated` lifecycle with key contacts, tags, and markdown documentation.

**Dataset metadata tools** (`qlik_update_dataset_metadata`, `qlik_update_dataset_quality`, `qlik_get_dataset_quality_computation_status`, `qlik_get_dataset_memberships`): Update dataset descriptions/tags, trigger quality computations, and check data product memberships.

**Potential framework usage:**
- During documentation generation: create glossary entries from the data dictionary, linking terms to master items created during visualization scaffolding.
- Post-pipeline: Package pipeline outputs into governed data products. Update dataset metadata with framework-generated descriptions.

The tool definitions document these tools' parameters thoroughly. Consult them directly when using governance features.

## Extensibility

When the Qlik Cloud MCP server adds new tools:

1. Test the tool against a live tenant to understand actual behavior.
2. Add any behavioral notes not covered by the tool definition to `references/behavioral-notes.md`.
3. Update the Tool-to-Task Mapping table in this file.
4. If the tool enables a new workflow pattern, add it to Section 5.
5. Update affected agent definitions if the new tool changes which agents need this skill.
