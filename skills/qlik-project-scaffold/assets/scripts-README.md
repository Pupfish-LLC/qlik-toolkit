# Scripts

Qlik load scripts (.qvs files):

- One file per logical script section (config, extract per source, transform, model load, calendar, variables, diagnostics) — or whatever organization suits the project.
- Shared subroutine libraries that are `$(Must_Include=...)`-ed by app scripts.
- A `script-manifest.md` documenting file purposes, dependencies, and run order if scripts are non-trivial.

The Qlik app's script editor pulls these in via `$(Include=lib://...)` / `$(Must_Include=lib://...)` from a DATA FILES space, or by copy-paste.
