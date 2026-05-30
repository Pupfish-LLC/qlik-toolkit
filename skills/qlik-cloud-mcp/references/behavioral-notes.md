# Qlik Cloud MCP — Per-Tool Behavioral Notes

These notes document behaviors discovered through live testing against Qlik Cloud that go beyond what the MCP tool definitions provide. Organized by tool category. Only read the sections relevant to your current task.

## Table of Contents

1. [App Inspection Tools](#1-app-inspection-tools)
2. [Data Analytics Tools](#2-data-analytics-tools)
3. [Visualization Creation Tools](#3-visualization-creation-tools)
4. [Dataset and Catalog Tools](#4-dataset-and-catalog-tools)
5. [Lineage Tools](#5-lineage-tools)
6. [Governance Tools](#6-governance-tools)

---

## 1. App Inspection Tools

### qlik_describe_app
- Safe, read-only metadata call. No significant gotchas.
- Less field detail than `qlik_get_fields`. Use `qlik_describe_app` for a quick overview, `qlik_get_fields` for type-level profiling.

### qlik_get_fields
- The `tags` array is the richest metadata source. Key tags to watch for:
  - `$key` — Qlik identified this field as a key (used in associations).
  - `$keypart` — Part of a composite key.
  - `$numeric`, `$text`, `$date`, `$timestamp` — Dual representation indicators.
  - `$ascii` — Text encoding indicator.
- **Does NOT return table membership.** You cannot tell which table a field belongs to from this response alone. That information comes from the load script or data model specification.
- Field names are case-sensitive throughout Qlik. `[Sales.Amount]` and `[sales.amount]` are different fields.

### qlik_get_field_values
- `limit` cap is not specified in tier-1 docs. Values up to ~99 have been observed to work reliably in testing; higher values may fail on some tenants. When in doubt, keep `limit` at or below the values used in this skill's examples (e.g., `limit=20`) and paginate for larger samples.
- Values are returned in Qlik's internal sort order, not alphabetical.
- **Affected by active selections.** If you need the full unfiltered value set, call `qlik_clear_selections` first.
- Does not return null counts. Use `qlik_create_data_object` with `NullCount()` for null analysis.
- Returns dual representation (text + numeric) for each value.

### qlik_search_field_values
- `fieldName` is required per the documented signature: `qlik_search_field_values(fieldName="payment_year", searchTerms=["2022"])`. To scan many fields, iterate the call per field.
- Case-insensitive (practitioner observation, unverified in docs).
- Partial matching (practitioner observation, unverified in docs).
- Numeric search works on the text representation, e.g. "2024" matches the text "2024" (practitioner observation, unverified in docs).

### qlik_list_sheets
- **The `cells` array in the response is truncated.** Never rely on it for a complete object inventory. Always follow up with `qlik_get_sheet_details` per sheet.

### qlik_list_bookmarks / qlik_create_bookmark / qlik_select_bookmark / qlik_delete_bookmark
- `qlik_select_bookmark` applies the bookmark's saved filter state to the session and returns the resulting selection state.
- `qlik_delete_bookmark` restriction: "You can only delete bookmarks created using Qlik MCP tools." Pre-existing user-created bookmarks cannot be removed via MCP.
- For reference-app analysis, `qlik_list_bookmarks` + `qlik_select_bookmark` is the cleanest way to reproduce a documented analytical context before extracting chart data.

### qlik_get_sheet_details
- Returns object configurations but NOT visual layout coordinates (grid row/column positions).
- Reliable for extracting chart types, dimension/measure assignments, and object IDs.

### qlik_list_dimensions / qlik_list_measures
- Returns all master (library) items with their definitions, expressions, and IDs.
- The `libraryId` from these responses is what you pass to `qlik_add_chart` when referencing master items.

---

## 2. Data Analytics Tools

### qlik_create_data_object
- **Session-scoped (ephemeral).** Objects exist only for the current session and are automatically cleaned up. No manual deletion needed.
- **Silent field name failures.** Referencing `[NonExistent.Field]` returns null/0, not an error. This is the most dangerous gotcha. Always verify field names with `qlik_get_fields` before building expressions.
- **Silent value failures in set analysis.** `Sum({<State={'XX'}>} [Amount])` returns 0 when 'XX' doesn't exist, not an error.
- **Label is mandatory for inline expressions.** Omitting `label` when using `expression` causes an error.
- **Label is ignored for library measures.** When using `libraryId`, the library item's label is used regardless of any `label` you provide.
- **Respects active selections.** Use set analysis for one-off filtering instead of `qlik_select_values` when you don't want to affect session state.
- **Data returned in first page only for large results.** Use `qlik_get_chart_data` with the returned object ID to paginate through larger result sets.
- **10,000 cell limit per request.** Cells = dimensions × measures × rows. Apply sort + limit to constrain high-cardinality dimensions.

### qlik_get_chart_data
- Works on both permanent chart objects (on sheets) and session objects (from `qlik_create_data_object`).
- The `chartId` for session objects is returned in the `qlik_create_data_object` response.
- Data reflects current selection state at time of call.
- Same 10,000 cell limit applies.

### qlik_get_chart_info
- Metadata only, no data retrieval. Returns chart type, title, dimensions, measures, total row count.
- Useful for inspecting reference app charts without loading their data.

### qlik_select_values
- **Cumulative and persistent.** Each call adds to existing selections. To replace, clear first.
- **Silent failure for non-existent values.** The returned selection list is the ground truth. If the field doesn't appear in it, the selection failed silently.
- **`match` overrides `values`.** If both are provided, only `match` is used.
- **Cannot clear app-level defaults.** Script-embedded selections, Section Access reductions, and default bookmark selections persist even after `qlik_clear_selections`.
- Prefer set analysis over selections for single analytical queries to avoid state management overhead.

### qlik_clear_selections
- Clears user-applied selections only. App-level defaults persist.
- Returns the actual selection state after clearing (the truth).
- Accepts optional `fieldName` to clear only one field's selections.

### qlik_get_current_selections
- Call before any data retrieval to check for unexpected active selections.
- Call after `qlik_select_values` to verify selections were applied correctly.

---

## 3. Visualization Creation Tools

### qlik_create_sheet
- Title must be 3-127 characters.
- Creates an empty sheet. Use `qlik_add_chart` and `qlik_add_filter` to populate it.
- No control over sheet ordering within the app.

### qlik_add_chart
- **No positioning control.** Charts are appended sequentially. No way to specify grid row/column.
- **No formatting control.** Colors, number formats, conditional formatting, fonts are not configurable.
- **Expression validation is deferred.** Invalid expressions succeed at chart creation but fail at render time (showing an error in the chart object). Always validate expressions with `qlik_create_data_object` first.
- **`label` is mandatory for inline fields/expressions.** Always include `label` when using `field` or `expression` directly (not `libraryId`).
- **Scatterplot requirements:** Despite documentation suggesting 2 dimensions + 1 measure, scatterplots actually work best with 1 dimension + 2-3 measures (X-axis, Y-axis, optional bubble size). Test your specific configuration.

### qlik_add_filter
- No control over filter display mode (list, search, dropdown). The Qlik Sense client determines this based on field cardinality.
- No control over positioning within the sheet.

### qlik_create_dimension / qlik_create_measure
- Name must be 3-127 characters for both.
- Once created, items are available to all sheets in the app.
- **Expression validation does not happen at creation time** for measures. Invalid expressions silently succeed here.
- **MCP-only mutation restriction (server-enforced):** Per the documented MCP contract — "You can only update and delete master items created using Qlik MCP tools." — `qlik_update_*` / `qlik_delete_*` can only act on items created via `qlik_create_*` within MCP. Pre-existing user-created items are read-only through MCP.
- **Published app restriction (platform-level, separate from the MCP rule):** In published apps (managed spaces), master-item edits must be made in the source app and re-published. This is a Qlik Sense rule and is independent of the MCP-only mutation restriction above.
- **Rename/delete propagation:** If a master measure is renamed or deleted, expressions referencing it by name return NULL rather than raising an error. References are not auto-updated.

### qlik_update_dimension / qlik_update_measure
- **MCP-only mutation rule:** Per the official server contract, only master items created via `qlik_create_dimension` / `qlik_create_measure` can be updated. Attempts to update pre-existing user-created items will fail.
- Useful for iterative scaffolding when an earlier `qlik_create_*` call produced an incorrect expression or label.

### qlik_delete_dimension / qlik_delete_measure
- **MCP-only mutation rule** applies identically (see above).
- References to a deleted master item by name return NULL silently at expression evaluation time (see rename/delete propagation note above).

---

## 4. Dataset and Catalog Tools

### qlik_search
- Searches applications, datasets, data products, and glossaries. Spaces and users are NOT searchable resource types via this tool.
- Use `resourceType` filter (e.g., "app,dataset") to narrow results.
- Paginated via `next` token.
- Resolving a space by name to a space ID is not available via the Qlik Cloud MCP server; obtain the ID from the Qlik Cloud UI (Spaces → space details URL) or the REST `/spaces` endpoint outside MCP. (Some other tools — e.g., `qlik_update_activate_data_product` — do accept a `spaceId` parameter; pre-resolve the ID before calling them.)

### qlik_get_dataset
- Returns the QRI (Qlik Resource Identifier) needed for `qlik_get_lineage`.
- Dataset types include QVD, CSV, and other Qlik-native formats.

### qlik_get_dataset_schema
- Data types are Qlik-native: STRING, DOUBLE, INTEGER, TIMESTAMP, DATE. These are not source database types.
- `primaryKey` flag may or may not be populated depending on how the dataset was registered.

### qlik_get_dataset_sample
- Fixed at 10 rows. No way to request more.

### qlik_get_dataset_profile
- Profile data may be stale or absent if the dataset hasn't been profiled recently.
- Check the profile timestamp. Use `qlik_update_dataset_quality` to trigger a fresh computation if needed.
- Not all datasets have profiles computed.

### qlik_get_dataset_freshness
- Returns last updated timestamp. No gotchas.

### qlik_get_dataset_trust_score
- **Returns an error when no trust score exists** (not null, not zero — an actual error). Most datasets won't have trust scores unless explicitly assessed. Handle this gracefully: log "trust score not available" and continue.

### qlik_get_dataset_memberships
- Returns which data products include this dataset. Paginated.

---

## 5. Lineage Tools

### qlik_get_lineage
- **One level deep per call.** Returns only immediate upstream dependencies.
- **Recursive calls required for full lineage.** For a pipeline like Source → Extract App → QVD → Transform App → Final App, you need 3+ calls.
- **QRI format must be exact:**
  - Apps: `qri:app:sense://[appId]`
  - Datasets: Get the QRI from `qlik_get_dataset` response (format varies).
- Not all resources have lineage metadata. Some apps or datasets may return empty results.
- **Lineage stops at the tenant boundary.** External sources outside Qlik Cloud (ODBC/REST endpoints, source databases) appear as a single terminal node; source-system-side lineage is not retrievable via MCP. For `LIB CONNECT` to ODBC/REST sources, the chain ends at the connection name, not the source table.

---

## 6. Governance Tools

### Glossary tools
- `qlik_update_term_status` accepts exactly `draft`, `verified`, or `deprecated` (case-sensitive).
- Only stewards can verify terms. Once verified, only stewards can modify the term.
- `qlik_get_full_glossary_export` is expensive — retrieves the entire glossary including all terms, categories, and links. Use `qlik_search_glossary_terms` for targeted queries instead.
- `qlik_create_glossary_term_links` supports both single and batch modes. When linking to subresources (field, master_dimension, master_measure), all three subresource fields (subResourceId, subResourceName, subResourceType) must be provided together.

### Data Product tools
- `qlik_update_data_product` uses patch operations for datasets, tags, and key contacts (op: add/remove/replace).
- `qlik_update_activate_data_product` requires name and spaceId. Activating makes the data product visible and consumable.
- `qlik_delete_data_product` is permanent and irreversible.

### Dataset metadata tools
- `qlik_update_dataset_quality` triggers an async computation. Returns a computation ID. Poll status with `qlik_get_dataset_quality_computation_status`.
- `qlik_update_dataset_metadata` uses patch operations for tags (op: add/remove/replace).
