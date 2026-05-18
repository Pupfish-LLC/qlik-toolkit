---
name: qlik-project-scaffold
description: Initialize a new Qlik project workspace with a standard directory structure (data sources, scripts, QVDs, documentation, tests). Cross-platform (Windows PowerShell and POSIX shell), idempotent (existing files are preserved), unopinionated about workflow. Use when starting a new Qlik Sense project and you want a baseline folder layout.
user-invocable: false
---

# qlik-project-scaffold

## Overview

Scaffolds a baseline directory structure for a new Qlik Sense project. Creates an opinionated-but-minimal folder layout that fits most Qlik development workflows. Does not impose any particular pipeline, methodology, or process — just gives the project a sensible starting structure.

The scaffold is **idempotent**: re-running on an existing project preserves all existing files. The scaffold only creates directories and `README.md` files that don't already exist.

## Directory Structure Created

```
project-root/
├── data-sources/           # Read-only source documentation, ER diagrams,
│   └── README.md           # connection specifications, sample data files
├── scripts/                # Qlik load scripts (.qvs files), shared
│   └── README.md           # subroutine libraries, script templates
├── qvds/                   # QVD output: optional. Use only if QVDs are
│   └── README.md           # stored alongside the project (not in Qlik's
│                           # data connections)
├── documentation/          # Project documentation: data model spec,
│   └── README.md           # expression catalog, visualization guide,
│                           # deployment runbook
└── tests/                  # Diagnostic / validation scripts run against
    └── README.md           # the loaded model after reload
```

This structure is a starting point, not a mandate. Drop directories you don't need; add directories the project requires.

## Usage

The agent or user invoking this skill should specify the project root. The skill then runs the creation procedure for that root.

### Cross-platform creation procedure

**PowerShell (Windows):**

```powershell
$projectRoot = "."  # or absolute path
$dirs = @("data-sources", "scripts", "qvds", "documentation", "tests")
foreach ($d in $dirs) {
    $path = Join-Path $projectRoot $d
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
    $readme = Join-Path $path "README.md"
    if (-not (Test-Path $readme)) {
        # Write the directory's README from the templates below
    }
}
```

**Bash (POSIX, macOS / Linux / Git Bash on Windows):**

```bash
project_root="."  # or absolute path
for d in data-sources scripts qvds documentation tests; do
    mkdir -p "$project_root/$d"
    if [ ! -f "$project_root/$d/README.md" ]; then
        # Write the directory's README from the templates below
        :
    fi
done
```

Both forms preserve existing files. Existing `README.md` content is never overwritten.

## README Templates per Directory

When creating each directory's `README.md`, use these templates (only if no README already exists):

### `data-sources/README.md`

```markdown
# Data Sources

Read-only source materials and reference documentation:

- Source system documentation (table schemas, ER diagrams, lineage)
- Sample data files (CSV, Excel exports) used during development
- Existing app references (.qvs scripts from production apps, .qvf exports)
- Platform documentation (naming conventions, deployment standards)

This directory is for *reading*, not *writing*. Outputs from the project go elsewhere (scripts/, qvds/, documentation/).
```

### `scripts/README.md`

```markdown
# Scripts

Qlik load scripts (.qvs files):

- One file per logical script section (config, extract per source, transform, model load, calendar, variables, diagnostics) — or whatever organization suits the project.
- Shared subroutine libraries that are `$(Must_Include=...)`-ed by app scripts.
- A `script-manifest.md` documenting file purposes, dependencies, and run order if scripts are non-trivial.

The Qlik app's script editor pulls these in via include statements or copy-paste.
```

### `qvds/README.md`

```markdown
# QVDs (Optional)

QVD output directory. Use only when QVDs are stored alongside the project files (e.g., for source control or local development).

In production, QVDs typically live behind Qlik data connections (`lib://...`) — not in the project repo. If that's your setup, you can delete this directory.
```

### `documentation/README.md`

```markdown
# Documentation

Project documentation:

- Data model specification (tables, fields, key relationships)
- Expression catalog (master measures and dimensions with full syntax + business meaning)
- Visualization guide (per-sheet purpose and interactions)
- Deployment runbook (Cloud or client-managed deployment steps)
- User guide (for business audience)
- Change log

Use audience-calibrated writing: technical docs for developers, plain language for business users. Never mix audiences within a single document.
```

### `tests/README.md`

```markdown
# Tests (Optional)

Diagnostic and validation scripts that run after a reload:

- Row count validation per table
- Null rate checks for key fields
- Referential integrity checks (orphans, duplicate keys)
- Value distribution checks

These are typically invoked manually or as part of a CI/CD process. If you don't run automated tests against your Qlik model, you can delete this directory.
```

## Notes

- **Idempotent.** Re-running on an existing project preserves all files. Only missing directories and missing READMEs are created.
- **Cross-platform.** Works on Windows (PowerShell) and POSIX (bash, zsh). Pick the form that matches your shell.
- **Unopinionated.** No pipeline phases, no required state files, no enforced workflow. The structure supports common Qlik dev patterns but doesn't impose one.
- **Customizable.** Add or remove directories based on your project's needs. The five defaults are a sensible starting point, not a mandate.
- **No `.gitignore`** is created by default — that's project- and team-specific. If you want one, add it after scaffolding with patterns appropriate for your VCS setup (e.g., `qvds/*.qvd`, `*.qvf`, `*.log`).
