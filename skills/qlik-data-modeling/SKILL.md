---
name: qlik-data-modeling
description: "Star schema design, key resolution (natural/composite/hash/AutoNumber), synthetic key prevention, circular reference resolution, QVD layer architecture, multi-app patterns (single app, generator/consumer, extract-transform-model-UI, binary load), source architecture consumption (dimensional warehouse, OLTP, Data Vault 2.0, pre-joined views, flat files), grain alignment across multiple facts, bridge tables, link tables, ApplyMap vs dimension, HidePrefix/HideSuffix. Load when designing or reviewing a Qlik Sense data model, deciding between single-app and multi-app, choosing a key strategy, or diagnosing synthetic keys and circular references."
user-invocable: false
---

# Qlik Data Modeling

Qlik Sense's associative engine links tables through identically-named fields — there is no explicit JOIN syntax at the model level. This makes **field naming a structural decision**: two tables sharing a field are automatically associated, and two tables sharing more than one field produce a synthetic key. Every model choice in this skill flows from that fact.

This skill covers data-model structure only. For script mechanics (LOAD syntax, QVD optimization rules, incremental patterns, SET/LET) see `qlik-load-script`. For naming conventions see `qlik-naming-conventions`. For expressions see `qlik-expressions`.

## 1. The One-Key Rule

**Every pair of associated tables should share exactly one field name.**

- Zero shared fields → the tables are **data islands**; selections do not propagate.
- Exactly one shared field → a clean association.
- More than one shared field → a **synthetic key** (Qlik creates a `$Syn` table, solid connector lines).

Non-key fields must be made unique across the model, typically via entity-prefixed dot notation: `[Product.Status]`, `[Order.Status]`, `[Customer.Region]`. Key fields must match exactly across tables that should associate. See `qlik-naming-conventions` for the full convention.

## 2. Synthetic Keys vs Circular References — Different Problems, Different Fixes

These are often conflated. They are not the same thing.

| | Synthetic Key | Circular Reference |
|---|---|---|
| **Cause** | Two tables share >1 field name | Closed loop of single-field associations A↔B↔C↔A |
| **Viewer signature** | `$Syn` table with **solid** connector lines | **Dotted** connector line on a *loosely coupled* table |
| **Failure mode** | Silent incorrect filtering; extra associations | Loosely coupled table does **not** propagate selections |
| **Fix** | Entity-prefix non-key fields, drop redundant shared fields, or use `ApplyMap` for lookups | Consolidate redundant key paths into one dimension, or introduce a link table; do **not** leave Qlik to pick a loose-coupling victim |

Common triggers for synthetic keys: unprefixed `Status`/`Code`/`Type`/`Name`; technical fields like `load_datetime`/`source_system` in multiple raw tables; wildcard LOADs from shared subroutines. Fix by entity-prefixing non-key fields or dropping technical fields.

`QUALIFY` is one tool for preventing synthetic keys on raw loads, but **do not combine QUALIFY with a hand-maintained prefix convention** — you will end up with `Table.Entity.Field` double-prefixed names and silent expression failures. Pick one discipline.

See `references/anti-patterns.md` (#1, #3, #4) for synthetic-key triggers, prevention mechanisms, the circular-reference comparison, and the QUALIFY failure modes.

## 3. Star Schema

A fact table surrounded by dimension tables, each linked by a single key.

- **Fact:** event-oriented, measure-bearing (`[Order.Amount]`, `[Sales.Quantity]`), every row at the same **grain**.
- **Dimension:** descriptive attributes (name, category, hierarchy), slower-changing.
- **One key per dimension:** each dimension links to the fact through exactly one key. If a dimension seems to need two keys, you probably need a link table or composite surrogate.

For one-to-many dimension attributes (product → multiple categories), use a **bridge table** rather than flattening into a delimited string. Use the **aliased EXISTS** pattern to add "No Entry" rows for parent entities that have no bridge entry, so they remain visible when the bridge is filtered.

Flattening via `LEFT JOIN` prefix is only appropriate for genuinely 1:1 relationships with a well-defined dedup rule. Default to bridge tables for many-to-many.

See `references/star-schema-patterns.md` for bridge-table construction, link tables, and `ApplyMap` patterns.

## 4. Key Resolution Strategy

| Situation | Key type | Why |
|---|---|---|
| Single source, reliable unique ID | **Natural key** | Readable, debuggable, matches source |
| Multi-source, need composite uniqueness | **Hash composite** — `Hash128(a, '|', b)` | Deterministic across reloads, safe to persist to QVD |
| Storing surrogate in a QVD for incremental matching | **Hash128 / Hash256** | Deterministic; `AutoNumber` is not |
| Final in-memory model load, very large string keys | **`AutoNumber`** | Memory savings; never in a stored QVD |

**AutoNumber is non-deterministic across reloads.** Two runs can assign different integers to the same business key. Never use it in the QVD layer or anywhere its output is compared across reloads — it will silently break incremental-load matching and cause duplicates to accumulate. Reserve it for the final model load that is not stored.

## 5. QVD Layer Architecture

QVDs are Qlik's compressed column-store files. Layering them decouples extraction from consumption and enables incremental loads.

**Three layers (large/complex projects):**

| Layer | Purpose | Refresh |
|---|---|---|
| **Raw** | Extract source as-is; `Raw_*.qvd` | Incremental per source |
| **Transform** | Clean, prefix, apply business rules; `Transform_*.qvd` | Depends on Raw |
| **Model** | Star schema assembly, composite keys; `Model_*.qvd` | Depends on Transform |

**Two layers (simpler projects):** collapse Raw + Transform into a single `Extract_*.qvd` step, then Model.

### Optimized QVD Read

An "optimized" QVD read is substantially faster than a standard (unpacked) read and an order of magnitude faster than re-querying the source. Preserve it with:
- `LOAD *`, field subsetting, field aliasing (`source AS [New.Name]`)
- `LOAD DISTINCT`, `CONCATENATE` load
- **Single-parameter** `EXISTS(field)` / `NOT EXISTS(field)` — the standard incremental pattern
- A preceding LOAD above the QVD LOAD (the inner QVD read stays optimized)

Forced to standard read by: any function/expression on a field (`Upper(name)`), derived fields (`a & '-' & b`), `WHERE` clauses other than single-parameter `EXISTS`, two-parameter `EXISTS(field, expr)`.

Full rules are in `qlik-load-script` → `qvd-operations.md`.

## 6. Multi-App Architecture

Single-app vs multi-app is a deployment decision. This section covers the **structural mechanics** of each pattern — how layers separate, what each app can customize, and what binary load does and does not copy. The **WHEN-to-split signals** (volume, refresh SLA, consumer count, team boundaries) live canonically in `qlik-performance` § 1 "Architecture-Level Decisions"; for the GB-anchored heuristics behind those signals see `references/multi-app-architecture.md`.

| Structural mechanic | Single App | Generator / Consumer | Extract → Transform → Model → UI | Binary Load |
|---|---|---|---|---|
| Independent layer refresh | no | yes | yes | no |
| Per-consumer model customization | n/a | yes | yes | **no** |
| Incremental load support | yes | yes | yes | **no** (full reload only) |

**Binary Load** copies the entire data model (and section access) from another app. Must be the **first statement** in the script. Syntax depends on platform:

- **Qlik Cloud:** accepts either an **app ID** from a tenant space — `binary [app_id];` (the most common cloud-native form) — or a **file path** to a .qvf/.qvw via a data connection to a file share — `binary [lib://DataConnection/path/Generator.qvf];`.
- **Client-managed (Enterprise on Windows):** `binary [lib://Apps/Generator.qvf];` — .qvf via folder data connection.

Binary load does **not** cascade reloads automatically, does **not** copy variables, sheets, visualizations, or master items. Consumer reloads must still be coordinated (event-based triggers / Qlik Automate in cloud; QMC task chains for client-managed).

See `references/multi-app-architecture.md` for full decision framework, reload coordination patterns, and common mistakes.

## 7. Source Architecture Consumption

Different upstream systems require fundamentally different consumption patterns. Treating them identically produces incomplete or wrong models.

| Source type | What to do |
|---|---|
| **Dimensional warehouse** (Kimball) | Usually load the star schema nearly as-is; validate SCD handling |
| **Normalized OLTP** (3NF) | Denormalize — either push the join into `SQL SELECT` at extract, or use `LEFT JOIN` prefix in Qlik Transform |
| **Data Vault 2.0** | Merge hub + current-version satellite into dimensions; for insert-only DV use `LoadDate` filter (canonical variant) or `LoadDate`+`LoadEndDate` (end-dated variant) |
| **Pre-joined views** | Validate grain before consuming — a "one row per customer" view often isn't; deduplicate if needed |
| **Flat files / CSV** | Set codepage, quote handling (`msq`), delimiter, validate headers; watch for file rotation |

Full patterns and worked examples are in `references/source-consumption-patterns.md`.

## 8. Grain Alignment Across Multiple Facts

When two fact tables at different grains (daily + monthly, order + invoice) share the same dimensions, connecting them directly to the same dimensions produces:

1. A synthetic key between the two facts (they share multiple dim keys).
2. Double-counted totals when expressions sum across both.

Pick one fix:

- **Concatenate** the facts into one table with a `[Fact.Type]` discriminator; require expressions to filter on it. Simplest when both facts measure the same thing at different granularities.
- **Link table** carrying the shared dim keys and `[Fact.Type]`; each fact associates to the link, the link associates to the dims. Use when the two facts measure genuinely different things.
- **Drop one of the facts** if the coarser grain is just a roll-up of the finer grain — keep the finer grain and let Qlik aggregate.

## 9. Supporting Files

- **`references/anti-patterns.md`** — Canonical home for data-modeling failure modes: synthetic keys (causes, detection, three prevention mechanisms), AutoNumber in QVD layer, circular references vs synthetic keys, QUALIFY discipline (double-prefix, missing UNQUALIFY, persistent state), multiple shared fields, missing bridge tables, wide-format expansion, ignoring source architecture, data islands, over-modeling, missing "No Entry" rows, grain misalignment.
- **`references/star-schema-patterns.md`** — Bridge tables with aliased EXISTS, link table construction, `ApplyMap` lookups, normalized-over-wide, key-hiding mechanics (HidePrefix/HideSuffix application — naming convention itself in `qlik-naming-conventions`), SubField expansion, dimension vs fact classification.
- **`references/multi-app-architecture.md`** — Single-app, generator/consumer, four-layer split, binary load (both platforms), reload coordination (Cloud events/Automate, QMC task chaining), common multi-app mistakes.
- **`references/source-consumption-patterns.md`** — Full per-source consumption patterns including Data Vault hub/satellite merge, OLTP denormalization (SQL-side vs Qlik-side), dimensional warehouse ingest, pre-joined view grain validation, flat-file ingestion with codepage and quote handling.

## Key Rules

1. One shared field per table pair. Zero means island, more than one means synthetic key.
2. Entity-prefix non-key fields. Don't combine QUALIFY with manual prefixing.
3. `$Syn` table with solid lines ≠ dotted loose-coupling line. Synthetic keys and circular references are different problems with different fixes.
4. Hash keys for anything persisted to a QVD. `AutoNumber` only in the final in-memory model.
5. Optimized QVD read is preserved by single-param `EXISTS` but broken by any function applied to a field.
6. `binary` syntax differs between Cloud (app ID) and client-managed (`lib://` .qvf path). It does not cascade reloads.
7. Pick the consumption pattern to match the source architecture — DV satellites must be merged, OLTP must be denormalized, pre-joined views must have their grain validated.
8. Two facts at different grains sharing dimensions → synthetic key + double-counting. Concatenate with a type discriminator, use a link table, or drop the redundant grain.
