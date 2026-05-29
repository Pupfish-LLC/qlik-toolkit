---
name: qlik-project-scaffold
description: "Qlik project directory layout convention for Claude-Code workflows: data-sources, scripts, qvds, documentation, tests directories with per-directory rationale and starter README templates. Cross-platform PowerShell + Bash scaffolding scripts that are idempotent (re-running preserves existing files). Load when starting a new Qlik Sense project, setting up a workspace for Claude to help with, or evaluating an existing project's directory layout against a baseline convention."
user-invocable: false
---

# qlik-project-scaffold

## Overview

A baseline directory convention for a Qlik Sense project being developed with Claude Code assistance. The layout separates source materials (read-only) from generated artifacts (scripts, QVDs, docs) and gives Claude consistent locations to look for and write each kind of file.

Opinionated-but-minimal. No pipeline, no workflow, no required state files. Drop directories the project doesn't need; add directories specific to the project.

## Directory Layout

```
project-root/
├── data-sources/      # Read-only source documentation, ER diagrams,
│                      #   connection specs, sample data files
├── scripts/           # Qlik load scripts (.qvs), subroutine libraries,
│                      #   script templates
├── qvds/              # Optional. QVD output if QVDs are stored
│                      #   alongside the project (not behind lib://)
├── documentation/     # Data model spec, expression catalog, viz guide,
│                      #   deployment runbook, user guide, change log
└── tests/             # Optional. Diagnostic / validation scripts run
                       #   after reload
```

## Why this layout fits Claude-Code workflows

- **`data-sources/` is read-only.** Claude reads schemas, ER diagrams, and sample files from here without risk of writing back over them.
- **`scripts/` holds the canonical `.qvs`.** When Claude authors or edits a load script, this is the single place to look. Pasting into the Qlik Sense script editor is a separate manual step.
- **`qvds/` is optional.** In production Qlik Cloud, QVDs typically live behind data connections (`lib://...`) in a DATA FILES space, not in the project repo. Keep this directory only for local development or source-controlled extracts.
- **`documentation/` is audience-calibrated.** Per-document audience matters (technical for developers, plain language for business). Never mix audiences inside a single file.
- **`tests/` runs against the loaded model.** Diagnostic `.qvs` snippets that validate row counts, null rates, and referential integrity after a reload.

## Creating the structure

Run the bundled scaffolding script. Both forms are idempotent and never overwrite existing files.

**Windows (PowerShell):**

```
.\scripts\scaffold.ps1 -ProjectRoot "C:\path\to\project"
```

**POSIX (bash, zsh, Git Bash):**

```
./scripts/scaffold.sh /path/to/project
```

Both scripts:

- Create the five directories if they don't exist.
- Copy the starter `README.md` for each directory from `assets/<dir>-README.md` if no `README.md` is already present.
- Preserve any existing file untouched.

If the project root is omitted, the script uses the current working directory.

## Starter README templates

Each directory gets a starter `README.md` describing its purpose and the conventions Claude should follow when reading or writing files in it. Templates live in `assets/`:

- [`assets/data-sources-README.md`](assets/data-sources-README.md)
- [`assets/scripts-README.md`](assets/scripts-README.md)
- [`assets/qvds-README.md`](assets/qvds-README.md)
- [`assets/documentation-README.md`](assets/documentation-README.md)
- [`assets/tests-README.md`](assets/tests-README.md)

Edit them in place after scaffolding to capture project-specific conventions.

## Notes

- **Idempotent.** Re-running on an existing project preserves all files. Only missing directories and missing READMEs are created.
- **Customizable.** Add or remove directories based on the project's needs. The five defaults are a sensible starting point, not a mandate.
- **No `.gitignore`** is created by default. Add one after scaffolding with VCS-appropriate patterns (e.g., `qvds/*.qvd`, `*.qvf`, `*.log`) if the project is source-controlled.
