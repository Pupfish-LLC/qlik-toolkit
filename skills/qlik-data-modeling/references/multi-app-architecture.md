# Multi-App Architecture Patterns

When and how to split a Qlik solution across more than one app: single-app, QVD generator/consumer, extract/transform/model/UI split, and binary load.

> The size thresholds below (GB of data, table counts, team counts) are practitioner heuristics, not Qlik-published limits. Use them as starting points, not hard rules. The real decision criteria are reload cycle time, number of consumer apps, team ownership boundaries, and refresh-schedule independence.

---

## Single App Pattern

All extraction, transformation, and modeling in one Qlik app. The simplest architecture and the correct starting point for most new projects.

### Suitable when

- Small data volume (rough heuristic: a few GB in memory).
- ≤ ~10 tables.
- One team owns the whole thing.
- All tables share a single refresh cadence.

### Pros

- One script, one reload, one thing to debug.
- No reload coordination required.

### Cons

- Reload cycle time is a hard ceiling on refresh frequency.
- Every consumer shares the same model — model changes affect everyone at once.
- Only one team can realistically own the script.

### Signals that it's time to upgrade

- The full reload takes longer than the refresh SLA requires.
- Two or more consumer apps are duplicating identical extract logic.
- Two teams need to refresh different parts of the data on different schedules.
- The source connection list has grown past what one script can comfortably own.

---

## QVD Generator / Consumer Pattern

The most common multi-app pattern in production. One (or more) generator apps extract and transform, storing results as QVDs. Consumer apps load those QVDs and build their own models and dashboards.

```
Source Systems
      |
      v
[Generator App: Extract + Transform, STOREs QVDs]
      |
      +---> [Consumer App 1: loads QVDs, builds model + UI]
      +---> [Consumer App 2: loads QVDs, builds model + UI]
      +---> [Consumer App 3: loads QVDs, builds model + UI]
```

### Pros

- **Source isolation.** Only the generator app holds database connections; consumer apps never touch the source.
- **Shared investment.** One extract feeds many dashboards.
- **Independent refresh.** Consumer apps can reload on different schedules than the generator (subject to the chaining described below).
- **Clear ownership.** Generator team owns extract + cleaning; consumer teams own analytics.

### Cons

- QVD files are now a managed artifact (storage, retention, backup, access).
- You need reload coordination — consumers must wait for the generator.
- If consumers load-and-then-drop fields from a QVD, the load is no longer optimized (any field list or transform change after the QVD read unpacks the file).

### 2-layer vs. 3-layer QVDs

**2-layer (Extract + Model):** the generator stores `Extract_*.qvd` (raw pull) and `Model_*.qvd` (transformed, ready to consume). Consumers read `Model_*.qvd`.

**3-layer (Raw + Transform + Model):** the generator stores `Raw_*.qvd` (source shape preserved), `Transform_*.qvd` (cleaned, business rules applied), and `Model_*.qvd` (star schema assembly). Consumers read `Model_*.qvd`.

Use 3-layer when the source list is long and complex, incremental extraction is sophisticated, or multiple downstream teams want to branch from the Transform layer. Use 2-layer when the transformations are straightforward and the extra layer adds no debugging value.

### Reload coordination

**Qlik Cloud** has native hub reload tasks with **event-based triggers** ("Another task succeeded" / "Another task failed"). Chain the generator's reload task to the consumers' reload tasks using the "On success" trigger. Qlik Automate (formerly Qlik Application Automation) offers a more flexible option with its "Do reload" block and richer branching logic.

**Qlik Sense client-managed (QSEoW)** has native task chaining in the QMC via "Task event" triggers (`TaskSuccessful` / `TaskFail`). External schedulers (Windows Task Scheduler, cron, enterprise ETL tools) are an option but **not** a requirement — QMC has handled this natively for years.

In both environments, the rule is the same: consumer reloads must not start until the generator's reload has finished successfully. If the generator fails, consumers either use the previous run's QVDs (stale but available) or are held back until it's fixed, depending on how you configure the trigger.

---

## Extract / Transform / Model / UI Split

A 4-layer split for very large or very governed projects. Each layer is a separate app, and each layer stores QVDs that the next layer consumes.

```
Source → [Extract app] → Raw_*.qvd
       → [Transform app] → Transform_*.qvd
       → [Model app]    → Model_*.qvd
       → [UI apps]      → dashboards
```

### Suitable when

- Data volume is large enough that running extract + transform + model in one app no longer fits the reload window.
- 30+ tables with many business rules.
- Three or more teams with clear ownership boundaries (data engineering, analytics engineering, BI).
- Each layer genuinely needs to refresh at a different cadence.

### Pros

- Each layer can be developed, tested, and reloaded independently.
- Clear governance: each layer has a documented "contract" — what it consumes, what it produces, what transformations it applies.
- Transform-layer outputs can be reused by multiple downstream Model apps; Model-layer outputs can be reused by multiple UI apps.

### Cons

- Four reload cycles to monitor and chain.
- Three sets of QVDs on disk.
- Layer contracts need to be actively maintained as a deliverable in their own right.

### Layer contracts

Each layer should document:

- **Produces:** tables / fields stored as QVDs
- **Consumes:** tables / fields expected from the upstream layer
- **Transformations applied at this layer**

Example — Transform layer contract:

```
Consumes: Raw_Customer.qvd, Raw_Product.qvd, Raw_Order.qvd (per Extract contract)
Produces: Transform_Customer.qvd, Transform_Product.qvd, Transform_Order.qvd
Transformations:
  - Rename to entity-prefix notation ([Customer.Name], [Product.Category], ...)
  - Null cleaning via vCleanNull
  - Data quality validation (row count thresholds, key uniqueness)
```

Contracts make schema drift visible: if the Extract team renames a column, the Transform team's contract test fails, rather than the UI silently going blank.

---

## Binary Load

`binary` copies the entire data model from another Qlik app into the current app. Useful when a consumer needs the generator's exact model with no modifications.

### Rules

- `binary` must be the **very first statement** of the script, before any `SET`, `LET`, or `LOAD`.
- Only **one** `binary` statement per script.
- Reference syntax depends on the platform:
  - **Qlik Cloud (SaaS):** two accepted forms — reference the source app by its **app ID** from a tenant space (`binary [app_id];`, the most common cloud-native form), **or** reference a **.qvf / .qvw file path** via a data connection to a file share such as AWS S3 or Google Drive (`binary [lib://DataConnection/path/Generator.qvf];`).
  - **Client-managed (Qlik Sense Enterprise on Windows):** reference a **.qvf file path**, typically via a folder data connection, e.g. `binary [lib://Apps/Generator.qvf];`.
- Loads: data tables **and section access data**.
- Does **not** load: sheets, stories, visualizations, bookmarks, master items, variables, or the script itself.
- Additional `LOAD` / `SQL SELECT` statements after `binary` are allowed and will concatenate / add to the binary-loaded model.

```qlik
// Qlik Cloud — reference the generator app by ID (first line of script):
binary [a1b2c3d4-5e6f-7890-abcd-ef1234567890];

// Client-managed — reference the generator .qvf via a folder connection:
// binary [lib://Apps/Generator.qvf];

// Optional — augment the binary-loaded model with extra tables
[ExtraLookup]:
LOAD code, description FROM [lib://QVDs/Extra_Lookup.qvd] (qvd);
```

### When to use

- The consumer is a dashboard-only app that uses the generator's model unchanged.
- You want to avoid re-implementing the model in the consumer.
- You accept that the consumer re-reads the whole model on every reload (no incremental).

### What `binary` does NOT do

**It does not automatically cascade reloads.** The consumer only picks up new data when its own reload is triggered — `binary` is a load-time snapshot of the generator's last saved state, not a live link. If you want consumers to refresh after the generator, you must coordinate that with event-based triggers (Cloud) or QMC task chains (client-managed), exactly as with the QVD pattern.

**It does not transfer variables.** Variables defined in the generator's script are not carried over. If consumers need the same variables, re-declare them after the `binary` statement or include them via `$(Must_Include=...)`.

### Mixing binary with QVD loads

Mixing a `binary` load with QVD loads of the same tables is redundant — whatever comes from the QVDs will concatenate on top of what's already in the model, usually producing duplicated rows or unwanted associations. Either take the whole model from `binary`, or take the whole model from QVDs; don't overlap them for the same entities.

---

## Decision Framework

The practitioner heuristics in this table are starting points, not authoritative limits.

| Criterion | Single App | Gen / Con | Extract→Transform→Model→UI | Binary |
|---|---|---|---|---|
| Rough data volume | small (few GB) | medium | large | matches source model |
| Rough table count | ≤ ~10 | ~10–30 | 30+ | whatever source has |
| Teams involved | 1 | 1–3 | 3+ | 1 for the model |
| Refresh schedule independence | no | yes | yes | no (tied to generator) |
| Per-consumer model customization | n/a | yes | yes | no |
| Incremental load support | yes | yes | yes | no (full reload) |
| QVD storage footprint | none | medium | largest | none |
| Reload coordination complexity | none | medium | highest | low (still needs chaining for fresh data) |

**Quick decision guide**

1. **Start with Single App** unless one of the "signals to upgrade" above already applies.
2. **Move to Generator / Consumer** when multiple consumer apps need the same data, or when reload cycle time becomes the bottleneck.
3. **Move to Extract/Transform/Model/UI** when the project has genuinely multiple teams with separate ownership boundaries, *and* the extra operational complexity is justified by the scaling or governance benefit.
4. **Use Binary Load** when and only when the consumer genuinely needs the generator's model unchanged, you accept full-model reloads, and you've set up explicit reload chaining.

---

## Reload Failure Handling

### Failure scenarios

- **Generator fails.** Consumers continue to read the previous run's QVDs (stale but available). Nothing automatic happens — an operator has to decide whether to hold consumers back or let them run on stale data.
- **One consumer fails.** Unaffected; other consumers and the generator run normally.
- **Network / storage failure.** Partial QVDs are the risk. Write to a staging location and rename on success so readers never see a half-written file.

### Practices worth having

- **Row-count sanity checks** inside the generator, after each STORE. TRACE a warning (or halt) if an entity drops below a floor or rises above a ceiling.
- **Freshness checks** inside consumers. Before building the model, verify the upstream QVDs exist and were updated recently.
- **Centralized reload logs.** Each app appends success/failure to a shared log QVD for operational visibility.
- **Deliberate halt semantics.** Use `EXIT SCRIPT` to abort a reload on validation failure. Setting `ErrorMode = 1` is the engine default and does not by itself stop anything — see the `qlik-load-script` skill for the correct error-handling framework.

```qlik
// Consumer freshness check
IF IsNull(FileTime('lib://QVDs/Transform_Product.qvd')) THEN
    TRACE [CRITICAL] Transform_Product.qvd missing -- generator likely failed;
    EXIT SCRIPT;
END IF

LET vQvdAge = Interval(Now() - FileTime('lib://QVDs/Transform_Product.qvd'), 'hh:mm');
TRACE Transform_Product.qvd age: $(vQvdAge);
```

---

## QVD Storage and Retention

### Storage location

**Qlik Cloud** uses **space-scoped data file connections**. QVDs live in a DataFiles connection inside a space, and are referenced as `lib://DataFiles/filename.qvd` (or `lib://SpaceName:DataFiles/filename.qvd` for a specific space). There is no per-app `DATA/[app-name]/` folder convention in Cloud — access is controlled by space permissions.

**Qlik Sense client-managed** typically uses a shared folder data connection pointing at a filesystem path the reload engine can reach — e.g., `\\fileserver\qlik\qvds\` or `/opt/qlik/qvds/`. Avoid storing shared QVDs inside individual app folders; that breaks the assumption that any consumer can reach them.

### Retention

- **Current QVDs** (the ones consumers read) — always kept, overwritten in place or atomically swapped.
- **Archived timestamped QVDs** (for incremental loads or audit) — retained per your reload pattern (e.g., last 30 dailies for a 30-day incremental window).
- **Failed partial QVDs** — cleaned up so that consumers never see half-written files. Atomic write + rename is the most robust pattern.

Qlik script does not have a native "delete file" statement — cleanup is handled by a scheduled OS-level task, a reload subroutine using `Execute` (client-managed only), or an external scheduler. Do not try to fabricate a delete inside a reload script.

---

## Summary

| Architecture | Best for | Reload coordination |
|---|---|---|
| Single App | Small data, simple models, one team | none |
| Generator / Consumer | Multiple consumers sharing extract + transform | event-based reload chain (Cloud) or QMC task chain (client-managed) |
| Extract→Transform→Model→UI | Very large projects with multiple teams and layer-level governance | sequential reload chain across 4 layers |
| Binary Load | Dashboard-only consumers needing the generator's exact model | chained reload (still required to refresh consumers) |
