# Subroutine Integration

Canonical reference for incorporating external `.qvs` libraries into a Qlik script: include directives, `CALL` syntax, variable scoping rules (the single biggest scoping trap in Qlik), `FOR EACH` iteration patterns, phantom-field detection after subroutine return, and composite key workarounds.

## Including External Files

`$(Must_Include=lib://Connection/path/file.qvs);` fails the reload if the file is missing.

`$(Include=lib://Connection/path/file.qvs);` silently skips a missing file. Useful for optional includes (e.g., environment-specific overrides) but unsafe for any include the script actually depends on.

**Rule:** Use `Must_Include` for required includes. Use `Include` only for genuinely optional ones, and pair it with a `TRACE` warning so a silent skip is visible in the reload log.

## Calling Subroutines

```qlik
$(Must_Include=lib://Shared/standard-libs.qvs);
CALL MySub(param1, param2);
```

`CALL` invokes a subroutine declared between `SUB` and `END SUB`. Arguments are positional. The `END SUB` keyword must appear on its own logical statement — missing it is the most common reason for a "subroutine not found" error elsewhere in the script.

## Variable Scoping — The Critical Gotcha

Qlik variables are primarily global. The single exception, documented by help.qlik.com:

- **Variables created inside a SUB with `LET` or `SET`** are global. They persist after the subroutine returns and will overwrite any caller variable of the same name.
- **Formal parameters declared in the SUB signature** (e.g., `SUB MySub(pArg1, pArg2)`) are locally scoped to that subroutine. Extra parameters beyond the actual arguments passed are initialized to NULL and can be used as local-only working variables.

### Practical rule

Use the SUB parameter list for anything that must not leak out. Use naming prefixes (e.g., `vSub_MySub_Counter`) for `LET`/`SET` variables that intentionally stay global. **Never rely on a bare `LET` inside a SUB for local state** — it pollutes the caller's variable space.

```qlik
// WRONG -- vCounter leaks to caller and overwrites any global of the same name:
SUB CountRows(pTable)
    LET vCounter = NoOfRows('$(pTable)');
    TRACE Table $(pTable) has $(vCounter) rows;
END SUB

// RIGHT -- pCounter is a formal parameter, locally scoped; no leak:
SUB CountRows(pTable, pCounter)
    LET pCounter = NoOfRows('$(pTable)');
    TRACE Table $(pTable) has $(pCounter) rows;
END SUB
```

## FOR EACH Loops

Iterate over file lists or value lists:

```qlik
FOR EACH vFile IN FileList('lib://Data/*.qvd')
    [_AllData]:
    LOAD * FROM [$(vFile)] (qvd);
NEXT vFile
```

**Cloud caveat:** In Qlik Cloud, wildcard file paths (`*`) may not be supported in all connection types. Use a directory listing or explicit file names if wildcards fail.

For value lists:

```qlik
FOR EACH vSource IN 'orders', 'shipments', 'returns'
    [$(vSource)]:
    LOAD * FROM [lib://RawData/$(vSource).qvd] (qvd);
NEXT vSource
```

## Phantom Field Prevention

Some shared subroutines initialize empty inline tables. If column parameters are wildcards or improperly specified, phantom fields appear in results. Always verify subroutine output contains only expected fields.

After calling a subroutine, check by iterating fields in script:

```qlik
FOR vFldIdx = 1 TO NoOfFields('$(vResultTable)')
    LET vFldName = FieldName($(vFldIdx), '$(vResultTable)');
    TRACE Field $(vFldIdx): $(vFldName);
NEXT vFldIdx
```

If a phantom field appears, `DROP FIELD [PhantomFieldName] FROM [$(vResultTable)];` after the subroutine returns. Document the workaround near the CALL site so future maintainers understand why the explicit DROP exists.

## Composite Key Workaround

When a subroutine handles only single keys but you need composite keys, two options:

- **Concatenate before, split after.** Build a composite string with a safe delimiter (`'|'` is conventional), pass it as a single key, and split back into parts on the return path.
- **Bypass the subroutine.** If the composite logic is simple enough, implement it inline rather than fighting the single-key signature.

```qlik
// Concatenate before call:
[Orders_Pre]:
LOAD
    [Region] & '|' & [Product] AS [%CompositeKey],
    [Amount]
RESIDENT [Orders];

CALL StandardKeyEnrichment('Orders_Pre', '%CompositeKey');

// Split after call (if the subroutine preserved the key):
[Orders_Final]:
LOAD
    SubField([%CompositeKey], '|', 1) AS [Region],
    SubField([%CompositeKey], '|', 2) AS [Product],
    [Amount]
RESIDENT [Orders_Pre];
DROP TABLE [Orders_Pre];
```

The delimiter must be a character that cannot appear in either source field. `|` is conventional; use a different character (or a multi-character separator) if `|` is a valid data value.

## See Also

- `../SKILL.md` § 18 — overview entry point that links here
- `../../qlik-platform-discovery/SKILL.md` — when working in a brownfield platform with a shared subroutine library, document the contract (signatures, side effects, phantom fields) in the platform context template before relying on subroutines in new scripts
