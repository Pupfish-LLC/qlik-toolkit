# Variable Input control (Dashboard Bundle) — pipe-delimited Dynamic values

The Variable Input control's **Dynamic values** mode reads a pipe-delimited string and tokenizes it into dropdown options. It does NOT enumerate a field's distinct values, even when the expression is a bare field reference. A bare `=[SomeTable].[SomeField]` resolves to one scalar (the first selected or loaded record) and the dropdown collapses to one entry or breaks.

The supported syntax is one of:

- **Value-only:** `value1|value2|value3` — dropdown displays and writes the same value.
- **Value-label:** `value1~label1|value2~label2|...` — dropdown displays LABEL, writes VALUE into the bound variable.

Build the string in the load script (recommended) or compute it inside the control expression (slower).

## Recommended: build the pipe string in the load script

Materialize the string once at reload using `Concat` and `Peek`, then expose it as a variable:

```qlik
[MeasuresMenu]:
LOAD * INLINE [
    %MeasureExpression,    %MeasureLabel
    vRevenueGross,         Gross Revenue
    vRevenueNet,           Net Revenue
];

[_MeasurePickerPipeBuild]:
LOAD
    Concat([%MeasureExpression] & '~' & [%MeasureLabel], '|') AS pipe
RESIDENT [MeasuresMenu];

LET vPipeMeasures = Peek('pipe', 0, '_MeasurePickerPipeBuild');
DROP TABLE [_MeasurePickerPipeBuild];
```

Then in the Variable Input control:

- **Dynamic values:** `='$(vPipeMeasures)'`
- **Bound variable:** whatever variable receives the selected value (e.g., `vSelectedMeasure`).

The control expands the variable, splits on `|`, and (for the `~` form) treats the right side of each pair as the visible label and the left side as the value written into the bound variable.

## Chart-side: double-dollar expansion when the variable holds a variable name

If the picker writes a *variable name* into the bound variable (the value-label form where each value is itself the name of a measure variable), the chart expression needs two rounds of dollar-sign expansion to dereference it to the actual measure:

```qlik
=$($(vSelectedMeasure))
```

The inner `$(vSelectedMeasure)` expands to the variable name (e.g., `vRevenueGross`). The outer `$()` expands that variable to its full expression (e.g., `Sum([Revenue.Gross])`).

Alternative when explicitness is preferred over indirection:

```qlik
=Pick(Match($(vSelectedMeasure), 'vRevenueGross', 'vRevenueNet'),
      $(vRevenueGross), $(vRevenueNet))
```

More verbose, grows linearly per measure, but no indirection — straightforward to read and debug.

## Alternative: build the pipe string inside the control expression

`Concat()` can be evaluated directly in the Dynamic values expression:

```
=Concat(DISTINCT [%MeasureExpression] & '~' & [%MeasureLabel], '|')
```

Works for small, stable lists. Degrades on large or selection-sensitive lists because Qlik re-evaluates the expression on every state change. For production, prefer the load-script materialization.

## Why the trap is sticky

The official Qlik Cloud docs (Dashboard Bundle → Variable Input control → Dynamic values) document the pipe-tilde syntax positively, but the negative — "you cannot just point at a field" — is implicit. The parameter name "Dynamic values" reads like it iterates a field; in practice it tokenizes a string. The script-side Concat-and-Peek pattern is the bridge between the associative engine's distinct-value awareness and the control's string consumption.

Reference: help.qlik.com Cloud → Dashboard Bundle → Variable Input control.

## See also

- `qlik-load-script` Section 7 (Data-Driven Patterns) → Concat-and-Peek for UI-variable build, for the general script-side technique.
