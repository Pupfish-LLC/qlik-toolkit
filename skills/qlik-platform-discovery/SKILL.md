---
name: qlik-platform-discovery
description: "Brownfield Qlik platform discovery: subroutine identification and limitation patterns from existing .qvs scripts, naming-convention variations (entity-prefix dot vs underscore vs camelCase; dim_/fact_ vs hub_/sat_/lnk_ vs Map_), connection conventions, QVD storage conventions (centralized layered vs per-app vs date-stamped), architecture pattern detection (single-app, generator/consumer, four-layer, binary load), incremental load detection, and convention-conflict resolution when platform conventions differ from framework defaults. Load when working in a brownfield Qlik environment, reverse-engineering an existing platform's conventions, or integrating new development with shared subroutine libraries."
user-invocable: false
---

## Why brownfield Qlik platforms need discovery

Most real Qlik environments inherit conventions — shared subroutine libraries, established naming standards, organization-specific data connections, opinionated QVD storage layouts, and deployment models that pre-date the current project. New development that ignores those conventions either fails to integrate (subroutines call missing fields, QVD paths don't resolve), violates local code standards (the new app feels foreign in a portfolio review), or duplicates work that a shared subroutine already handles.

The patterns below describe what to look for when reading existing `.qvs` scripts, when interviewing the developer about the platform, and when reconciling differences between platform conventions and the framework defaults this toolkit recommends elsewhere. For greenfield projects, skip to "Greenfield handling" near the end.

## Reading existing .qvs scripts

The most reliable platform context comes from existing scripts — they show actual subroutine signatures, naming patterns in use, connection names that resolve, and QVD storage conventions that work in production. If the developer can share one or more reference apps' scripts, those are the primary source.

### Subroutine identification

Every `SUB ... END SUB` block in a script is a candidate for reuse in new development. For each one, capture:

- **Name** (exactly as declared, case-sensitive).
- **Parameters** (declared in the `SUB Name(p1, p2, ...)` line). Parameters are positional — order matters.
- **Purpose**: inferred from the code body or any preceding comment block. If the body is short and obvious, describe it in one sentence; if the body is complex, describe the contract (what it expects, what it produces).
- **Known limitations**: what the subroutine does NOT handle. These are rarely obvious from code alone — look for `WHERE`, `EXISTS`, and `CONCATENATE` patterns that assume single-field keys, hardcoded table names, or wildcard SELECTs that would inject phantom fields if called from a different context. When a limitation isn't testable from the code, flag it as a question for the developer rather than assuming.
- **Call sites**: every `CALL SubName(...)` reference in the broader script base. Call sites show the operational signatures developers actually use, which sometimes diverge from the declared parameter intent.

Shared subroutine libraries are typically included via `$(Include=lib://path/file.qvs)` (silent skip if the file is missing) or `$(Must_Include=lib://path/file.qvs)` (reload fails if missing). The `Must_Include` form is the safer default for production libraries because it makes the dependency explicit. When a script uses `Include`, ask whether the optional behavior was intentional or whether `Must_Include` was meant.

### Naming-convention variations to expect

There is no single Qlik naming standard. Real platforms use one of several patterns, and brownfield platforms often mix patterns across legacy and newer apps. Identify the dominant pattern (>70% of artifacts) and note exceptions with frequency — this is signal about the platform's evolution, not noise.

**Field names** typically follow one of:

- **Entity-prefix dot notation** — `[Order.Date]`, `[Customer.Name]`. Matches the framework default (see `qlik-naming-conventions`).
- **Underscore separation** — `order_date`, `customer_name`. Common in OLTP-origin and dimensional-warehouse–origin platforms.
- **camelCase** — `orderDate`, `customerName`. Less common in Qlik specifically but present where the platform inherited conventions from a developer team coming from application-development backgrounds.
- **Source-passthrough** — fields kept as they appear in the source system, often a mix of patterns from different upstream sources.

**Table names** commonly use prefixes:

- `dim_` / `fact_` — dimensional-warehouse origin.
- `hub_` / `sat_` / `lnk_` — Data Vault 2.0 origin.
- `_` prefix (e.g., `_Temp_Orders`) — convention for temp/staging tables that should be dropped before QVD store.
- `Map_` — mapping tables intended for `ApplyMap()`.

**Variable names** commonly use:

- `v` prefix (`vCurrentYear`, `vLastReloadDate`) — framework default.
- No prefix at all — legacy QlikView-era scripts often lack a convention.
- Hungarian-style prefixes (`vd` for dates, `vn` for numbers, `vs` for strings) — present in some highly mature platforms.

**Composite keys** vary widely:

- `%CompositeKey` (leading `%`, hidden via `HidePrefix='%'`) — framework default.
- `_key` suffix.
- No discipline at all — composite keys constructed inline at JOIN time without a stored composite field.

When the dominant platform convention differs from the framework default, the project decides which to adopt; see "Convention conflicts" below.

### Connection conventions

Every `LIB CONNECT TO '[ConnectionName]';` and every `lib://ConnectionName/...` reference in load statements identifies an existing connection. Catalog:

- **Name** (exactly as written — connection lookups are case-insensitive but the recorded name should match for consistency downstream).
- **Type**: ODBC, OLEDB, REST, folder, S3, Google Drive, etc. Often visible from the connection's role (ODBC for database, folder for file system, REST for API).
- **Target**: server/database for ODBC, base URL for REST, root path for folder. Often not inferable from the script alone — ask the developer.
- **Environment variations**: dev/test/prod connection names commonly differ by suffix (`Warehouse_Dev`, `Warehouse_Prod`) or by an environment-variable lookup at script start. When a script does `LET vEnv = ...` followed by `LIB CONNECT TO 'Warehouse_$(vEnv)';`, the platform has an environment-switching pattern worth documenting explicitly.

### QVD storage conventions

QVD paths in `STORE` statements and `LOAD ... FROM ... (qvd)` statements reveal the platform's layered-storage convention. Common patterns:

- **Centralized layered store** — `lib://QVD/raw/`, `lib://QVD/transform/`, `lib://QVD/model/`. One root location with subfolders per ETL layer. Generally indicates a multi-app or generator/consumer architecture.
- **Per-app store** — `lib://AppData/orders_app/`. QVDs scoped to the producing app's folder. Common in single-app architectures and in environments where cross-app reuse is rare.
- **Date-stamped filenames** — `orders_20260301.qvd`. Indicates a partial-reload pattern or an archival convention. Worth asking whether old date-stamped QVDs are pruned or accumulate.
- **Layer-prefixed filenames** — `Raw_Orders.qvd`, `Transform_Orders.qvd`, `Model_Orders.qvd`. Layer identity in the filename rather than the folder.

### Architecture pattern detection

Script structure reveals the app-architecture pattern. Look for:

- **Single-app** — one app contains extraction, transformation, and model assembly. No QVD intermediate storage between layers (or QVDs used only for source-system speed reasons, not multi-app contracts).
- **QVD generator + consumer** — one app's purpose is to produce QVDs (its script ends in many `STORE` statements and the app has no UI sheets); another app's purpose is to consume QVDs (its script is dominated by `LOAD ... FROM ... (qvd)`). The QVD set is the contract between them.
- **Four-layer (extract / transform / model / UI)** — each layer is its own app with QVDs as the contract. Indicated by clearly named app suffixes (`OrderExtract`, `OrderTransform`, `OrderModel`, `OrderAnalytics`).
- **Binary load** — a downstream app reloads an upstream app's full data model via `Binary lib://...`. Indicated by a `Binary` statement at the top of the script with no other LOAD/SELECT before it.

The structural mechanics for each architecture pattern live in `qlik-data-modeling` → `multi-app-architecture.md`.

**Incremental load patterns** appear as:

- Single timestamp comparison (`WHERE modified_date >= '$(vLastReloadDate)'`) — most common.
- Dual-timestamp for Data Vault satellites (`WHERE load_date > '$(vLastLoad)' AND effective_date <= '$(vRunDate)'`).
- File-list patterns (load `orders_*.qvd` and dedupe) — common where source landings are date-stamped.
- Full reload (no incremental logic) — explicit choice for small or frequently-changing sources.

**Error-handling conventions** are platform-specific. Look for:

- `TRACE` discipline at layer boundaries (verbose logging vs minimal logging).
- `IF ScriptError > 0 THEN ... END IF` blocks after each major step.
- `EXIT SCRIPT WHEN ...` patterns for fast-fail behavior.
- Custom logging subroutines (often part of shared libraries).

## Subroutine limitation patterns

Subroutines in shared libraries are reused widely, which means their limitations propagate. The following limitations are common enough to check for explicitly:

- **Single-key assumption** — the body uses `WHERE FieldName = pKey` or `Hash128(pKey)` with one parameter; composite keys will not work without modification.
- **Wildcard SELECT** — the body does `LOAD * FROM ...` or `LOAD * RESIDENT ...`; fields not present in the expected schema can leak into the target table.
- **Hardcoded paths** — connection names or QVD paths written as string literals inside the SUB body; moving the SUB across environments requires patching.
- **Variable scope leakage** — SUBs that `SET vSomeVar = ...` without resetting leave state for the next caller. `LET` and `SET` inside SUBs write to global scope.
- **Missing `NoConcatenate`** — SUBs that load a temp table without `NoConcatenate` will silently concatenate into a previously loaded table with matching field structure. Especially dangerous when SUBs are called in loops.
- **Missing `DROP TABLE`** — SUBs that build temp tables but don't drop them leave residue in the final data model, which can cause synthetic keys.

When a limitation is identified, the workaround is rarely "modify the SUB" (shared library code is owned elsewhere). The usual workaround is a project-side wrapper or a side-stepping pattern: manual `CONCATENATE` + `WHERE NOT EXISTS` for composite keys, explicit `DROP FIELD` after the SUB for wildcard leakage, environment-specific override variables defined before the include, and so on.

## Convention conflicts

Brownfield platforms often have naming or storage conventions that differ from the framework defaults the rest of the toolkit recommends. This is a design decision point, not a failure.

Example: the framework's default key-field convention uses `_key` suffix (`product_key`, `order_key`), but a platform uses `_id` (`product_id`, `order_id`). The project has three options:

| Option | When it fits |
|---|---|
| **Adopt platform convention** | The platform has shared subroutines that depend on the naming, or the new app sits alongside many existing apps that already use it. Cost of deviating exceeds cost of conforming. |
| **Adopt framework default** | The platform is small, future apps will adopt the framework standard, and deviation cost is low. |
| **Hybrid** | Adopt platform convention for keys and shared-subroutine-touched fields; adopt framework default for new fields and non-shared elements. |

The decision is made by the project's architect after looking at the dependency surface. When shared subroutines deeply assume a convention — for example, a SUB that internally looks for fields ending in `_id` — the platform convention almost always wins. The convention decision belongs in the project's data-model design (see `qlik-data-modeling`); the role of platform discovery is to surface the conflict, not to resolve it.

## Greenfield handling

For projects with no existing platform artifacts — no shared subroutine library, no established naming convention, no reference apps to study — platform discovery still applies but produces a much shorter record: "framework defaults apply." The framework defaults across naming, QVD layout, variable prefixes, and connection patterns live in `qlik-naming-conventions`, `qlik-load-script`, and `qlik-data-modeling`. The greenfield decision record is simply "this project adopts framework defaults for all conventions" — written once, referenced as needed.

## Platform Context template

When platform-discovery findings need to be written down as a deliverable artifact — a six-section catalog covering subroutine inventory, naming convention map, connection catalog, reference-app analysis, upstream-architecture classification, and platform-constraints register — the structured template lives at `references/platform-context-template.md`. The template includes columns and worked examples for each section.
