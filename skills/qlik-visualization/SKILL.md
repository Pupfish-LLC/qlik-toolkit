---
name: qlik-visualization
description: "Chart type selection with decision criteria based on data relationships, sheet layout patterns on the Qlik Sense responsive grid, responsive design behavior, color and formatting standards including accessibility-safe palettes, filter pane and listbox design strategies, navigation flow, accessibility best practices, and reference-app reverse-engineering patterns. Load when designing or reviewing Qlik Sense sheets, choosing chart types, building KPIs, configuring filter panes, replicating a reference app's look-and-feel, or evaluating a layout's responsive behavior."
user-invocable: false
---

## Overview

This skill covers everything users see in Qlik Sense: sheets, charts, filter panes, KPIs, responsive behavior, colors, fonts, and accessibility. It does NOT cover data modeling (qlik-data-modeling), expression authoring (qlik-expressions), or load scripts (qlik-load-script). The key principle: **sheets organize by business workflow (what questions users need answered), NOT by data tables**. The viz architect uses this skill to select chart types, design layouts, configure filters, and catalog reusable patterns from reference apps. The skill emphasizes decision frameworks over specification lists.

---

## Section 1: Chart Type Selection Decision Framework

Do not choose chart types by guess. Use a decision framework based on the data relationship you're visualizing.

### Data Relationships and Appropriate Charts

**Comparison (How do these categories compare?)**
- **Best choice:** Bar chart (horizontal for long category names), column chart (vertical, especially for time periods), bullet chart (single measure with performance target)
- **Avoid:** Pie and donut charts for comparison. Human eyes cannot accurately compare slice sizes; use bar charts instead (especially for >3 categories)
- **Example:** "Which sales region had highest revenue?" → Horizontal bar chart with regions on Y-axis, revenue on X-axis

**Composition (What parts make up the whole?)**
- **Best choice:** 100% stacked bar/column chart, waterfall chart (shows how total builds/breaks down step-by-step), treemap (hierarchical composition with size encoding)
- **Avoid:** Pie charts (only in specific cases where exactly 2-3 slices and context demands "percent of whole" messaging; generally avoid)
- **Example:** "What departments contribute to total headcount?" → 100% stacked bar chart

**Distribution (How are values spread across a range?)**
- **Best choice:** Histogram (binned frequency distribution), box plot (quartiles and outliers — part of the Visualization Bundle, verify it is enabled), scatter plot (one measure on each axis showing density)
- **Avoid:** Line charts for non-time distributions
- **Example:** "How are employee salaries distributed across ranges?" → Histogram showing salary buckets and frequency

**Relationship (How do two variables correlate?)**
- **Best choice:** Scatter plot (two measures, optional third as size/color), bubble chart (three measures: X, Y, size), heat map (two dimensions with measure as color)
- **Avoid:** Line charts for non-sequential data relationships
- **Example:** "Does marketing spend correlate with sales revenue?" → Scatter plot with marketing spend (X), revenue (Y)

**Trend (How does a measure change over time?)**
- **Best choice:** Line chart (time on X-axis, trend visible), area chart (trend with magnitude emphasis), combination chart (line for trend + bars for volume)
- **Avoid:** Bar charts for time series (less efficient than line)
- **Example:** "How has monthly revenue trended over the past year?" → Line chart with months on X-axis

### Specialized Chart Types

**KPI object** — Single metric with large font. Use when the metric is critical to user decision, or as dashboard headline. Supports conditional coloring and conditional symbols (e.g., check mark, caution, X) configured via the KPI's color/symbol limits in **Appearance** (and refined with calculation conditions). Note: the standard KPI does not include up/down trend arrows; that pattern lived in the Multi-KPI chart, which is deprecated (no new instances since April 5, 2025; full removal May 2027). For trend visualization, use a separate trend line/spark chart next to the KPI. Example: "Total Sales YTD" KPI in top-left of executive dashboard, with a monthly spark line beside it.

**Table** — Detailed row-level data. Use when users need exact values, multiple columns from different tables, or custom sorting. Design heuristic (practitioner, not Qlik-prescribed): limit to roughly 15 columns to keep the table scannable, right-align numbers, add currency symbols, use alternating row background colors for readability.

**Gauge chart** — Circular progress indicator with meaningful maximum (quota, target %). Use sparingly; wastes space compared to KPI for raw numbers. Useful when dashboard space is severely constrained.

**Combo/Combination chart** — Multiple measures with different visualization types (bars + line on dual Y-axes). Design carefully: different Y-axis scales can be misleading. Label clearly which axis each measure uses. Prefer combo charts when the two measures share interpretive context (e.g., volume + cumulative sum, or count + rate over the same base) and avoid them when measures are independent — small-multiples or two stacked charts give viewers a fairer comparison.

**Mekko chart** — Two-dimensional composition where bar width encodes one share and stacked-segment height encodes another, so each rectangle's area shows joint share of total. Use for "which segment + sub-segment dominates the whole" questions where size encoding adds information beyond a plain stacked bar.

**Funnel chart** (Visualization Bundle — verify it is enabled in the tenant) — Sequential drop-off / conversion across an ordered stage list. Use for funnels like "leads → qualified → opportunity → closed-won" where stage-to-stage retention is the message.

---

## Section 2: Layout and Information Hierarchy

Apply to sheet design using Qlik Sense's responsive grid system.

### Information Hierarchy Principles

- **Top priority first** — KPIs and headline numbers across top (users scan top-left first), detail analysis below
- **Business workflow sequence** — Organize left-to-right, top-to-bottom in the order users ask questions. Example: "What was revenue?" (KPI top-left) → "What's the trend?" (chart top-middle) → "Which regions contributed?" (bar chart right)
- **One focused object > many small objects** — Avoid visual clutter. Use sheets to separate concerns (executive summary sheet, detail analysis sheet, operational monitoring sheet)
- **Calculation conditions** — Hide objects when data is insufficient. Example: "Show this chart only if Year is selected" prevents showing a meaningless trend when no year filter is applied
- **Whitespace** — Use grid gaps and padding to separate logical groups. Improves readability and reduces cognitive load

### Calculation Condition Syntax

A calculation condition is a Boolean expression set on a visualization's **Add-ons → Data handling → Calculation condition** property. The object renders only when the expression evaluates to true; otherwise the paired **Displayed message** property is shown in its place. Canonical forms:

- `GetSelectedCount([Field])>0` — render only when the user has made at least one selection in `[Field]`.
- `GetPossibleCount([Field])=1` — render only when current selections narrow `[Field]` to exactly one value (useful for "drill-down required" charts).

Pair every calculation condition with a meaningful Displayed message so users see why the object is empty (e.g., "Select a Year to view this chart").

### Responsive Grid Behavior

Qlik Sense responsive mode stacks objects vertically on smaller screens. Objects in top-left remain visible across screen sizes; lower-right objects may reflow below fold. Design: ensure single-column layout looks good on mobile. Test by resizing the browser window in the sheet editor — the live responsive layout renders directly (no separate "preview mode" toggle is documented).

### Layout Patterns

**Executive Dashboard** — 4-6 KPIs across top row, global filters on right, one large visualization below (trend or comparison), action buttons or drill-through links at bottom.

**Detail Analysis Sheet** — Filters along one edge (left or right depending on existing app conventions and reading direction; pick one and apply consistently across sheets), visualization grid filling the rest. Place the high-level overview chart top-opposite-the-filter-edge and the drill-down table beneath it. Users filter on the filter edge and see impact across visualizations.

**Drill-down Sheet** — Breadcrumb navigation at top, detail table with progressive disclosure, supporting charts below for context.

### Object Sizing Heuristics (relative to sheet width)

Since the responsive grid has no documented fixed column count, size objects in proportions rather than absolute columns:

| Object | Typical width | Typical height |
|---|---|---|
| KPI card | ~1/4–1/6 of sheet width (4–6 across a row) | 1 row strip |
| Bar/line/combo chart | ~1/3–1/2 of sheet width | 2–3 rows (leaves room for legend + interaction) |
| Table | full or near-full width | 3–4 rows (accommodate scrolling) |
| Filter pane | thin column (~1/5–1/4 of sheet width) | 3–4 rows |

Reduce Grid spacing (Wide → Narrow) when more granular placement is needed.

---

## Section 3: Color and Formatting Standards

### Color Assignment

- **Static mapping** — Same dimension value always gets the same color across all sheets. Example: "North region is always blue, South always red." Implement via master item color assignment or conditional coloring expressions.
- **Sequential scales** — For ordered numeric data (0-100% completion). Use light-to-dark gradient (white → light blue → dark blue).
- **Diverging scales** — For data with meaningful midpoint (e.g., -50% to +50% variance). Use red (negative) → white (zero) → green (positive).

### Accessibility-Safe Palettes

Qlik Sense ships custom-theme support (`theme.json`) that can declare a categorical palette of accessible colors at app scope, so every chart inherits the same colorblind-safe sequence without per-object expressions; viridis and cividis are well-tested hex sources to embed in such a theme (see help.qlik.com Cloud → "Custom themes").

- **Color blindness (general accessibility heuristic)** — Approximately 8% of men and ~0.5% of women have some form of color vision deficiency (most common: red-green). Use tested colorblind-friendly palettes (viridis, cividis from the matplotlib/seaborn ecosystem are widely cited; not Qlik built-ins — apply via custom themes, custom color expressions, or hex values). When red/green is necessary, also use pattern, size, or text labels to differentiate.
- **WCAG AA contrast (general web standard, not Qlik-specific)** — Per W3C WCAG 2.1 AA, body text should have ≥4.5:1 contrast with its background, large text (≥18pt regular or ≥14pt bold) and graphical elements like chart marks, axis lines, and UI components need only ≥3:1 (SC 1.4.3 and SC 1.4.11). KPI headlines in the recommended 48-60pt range qualify as large text (3:1 threshold); axis labels in the 12-14pt range are body text (4.5:1 threshold). Test with WebAIM Contrast Checker. Dark text on light background is always safe.
- **Recommended palette** — Blues, oranges, purples (avoid pure red/green combinations unless text labels are added)

### Number, Date, and Field Formatting

- **Currency** — Symbol + 2 decimals: "$1,234.56" (with thousands separator)
- **Percentages** — 1 decimal: "45.2%"
- **Large numbers** — Abbreviated with tooltip: "1.2M" (tooltip shows "1,234,567")
- **Dates** — Consistent format across sheets: "Jan 2024" or ISO format "2024-01-15" (clearer than "01/02/03")
- **Field labels** — Friendly names: "Product Category" not "PROD_CAT". Consistent terminology across sheets.
- **Font sizes (practitioner heuristic; Qlik docs do not prescribe pt sizes)** — Typical ranges: KPI headline ~48-60pt for at-a-distance readability, chart title ~16-18pt, axis labels ~12-14pt. Adjust to fit dashboard pixel dimensions.

---

## Section 4: Filter Design Strategy

### Global Filter Pane (Multi-Sheet)

Use when users need the same filter context across multiple sheets (Year, Region, Department apply to all analyses). Place in a consistent location (either left or right edge — pick one as the app-wide convention and stick to it; see Section 2's Detail Analysis Sheet pattern), so selections persist as users navigate sheets and they always know where to find filters. Design heuristic (practitioner, not Qlik-prescribed): low-cardinality fields work well as a direct list (Year, Region); for high-cardinality fields, expect users to use the filter pane's built-in text search.

### Sheet-Specific Filter Pane

Use when filter applies only to one or two sheets (example: "Product Detail Filter" for product analysis only). Reduce cognitive load by hiding irrelevant filters. Embed filter objects on the sheet itself, above visualizations.

### Alternate States for Comparative Analysis

Allow multiple independent filter contexts on the same sheet. Use for "Budget vs. Actual" or "This Year vs. Last Year" comparisons. First define alternate states for the app (managed alongside other app-level settings), then apply a chosen state to each visualization via its Appearance properties for alternate states. Exact menu labels and the precise navigation path may vary by Qlik Cloud release; refer to help.qlik.com Cloud → "Using alternate states for comparative analysis" for the current UI path. Caution: increases complexity; use only when comparing is core workflow.

### Field Selection for Filters

The Qlik Sense filter pane renders one way — a list of values inside a single object — rather than offering separate widget modes per cardinality. The decision is about what interaction users will rely on, given how many values are in the field:

| Cardinality | Recommended interaction model (practitioner heuristic; Qlik does not prescribe these thresholds) | Example |
|---|---|---|
| ≤20 values | All values visible at once — user scans and clicks | Region (4 regions) |
| 21-50 values | Most values visible, light scroll inside the pane | Sales Rep (30 reps) |
| >50 values | Rely on the search box; scrolling is not practical | Product SKU (10,000 SKUs) |
| Time | Button group or calendar (separate Dashboard Bundle controls) | Monthly data → button group; Daily → calendar picker |

---

## Section 5: Responsive Design Patterns

### Qlik Sense Responsive Grid

By default, Qlik Sense applies a responsive layout that "adjusts the sheet to the dimensions of the user's screen" (Qlik docs). Layout is fluid rather than tiered: there is no Qlik-documented Desktop/Tablet/Mobile breakpoint scheme, and no Qlik-documented fixed column count (community claims of "24 columns" are not tier-1). The one documented threshold is the 480-pixel "small screen" mode, in which web-browser users can navigate and select but cannot create or edit content. Authors can override responsive layout per sheet by switching Sheet size from Responsive to Custom (Sheet properties → Sheet size), with custom widths and heights between 300 and 4,000 pixels.

**Grid spacing** (Sheet properties → Grid spacing) controls cell density on the responsive sheet — settings are **Wide** (default), **Medium**, **Narrow**, or **Custom** (slider; higher = narrower spacing = more cells per sheet width). The actual cell count varies with the spacing setting, so positions should be reasoned about in proportions of sheet width rather than absolute column numbers.

### Design for Responsive

- **Priority objects** — Top-left objects remain visible across breakpoints. Lower-right objects reflow below fold on mobile.
- **Single-column layout** — Ensure objects look good stacked vertically. Not too tall, readable fonts.
- **Object sizing** — Use auto-width/height; avoid fixed pixels that break on mobile.
- **Filter pane behavior under constraints** — When sheet space is limited, the filter pane first reduces each dimension's size to fit all dimensions; if not all dimensions fit, a dropdown arrow appears below the displayed dimensions to access the rest (per Qlik filter pane docs). In the Qlik Analytics mobile app, the filter pane is a natively rendered visualization. There is no documented "hamburger menu" collapse pattern.
- **What to hide on mobile** — Decorative objects, secondary reference charts, wide tables. Use Responsive Visibility settings to hide below breakpoint.

### Testing

To validate responsive behavior, resize the browser window in the Qlik Cloud sheet editor and observe how objects reflow. The editor renders the live responsive layout — there is no separate "responsive preview" toggle documented. For higher confidence, test the published sheet on an actual mobile or tablet device, since native rendering in the Qlik Analytics mobile app can differ from browser layout.

---

## Section 6: Accessibility Best Practices

### Color Accessibility

- **Color blindness-safe palettes (general accessibility heuristic, not Qlik built-ins)** — Use tested palettes (viridis, cividis are widely cited from the matplotlib/seaborn ecosystem; apply in Qlik via custom color expressions or hex values). When color alone distinguishes data, add pattern, shape, or text label. Example: don't just color bars red/green; also label "On Track" / "Off Track".
- **WCAG AA contrast (general web standard, not Qlik-specific)** — Per W3C WCAG 2.1 AA, body text should have ≥4.5:1 contrast with its background (SC 1.4.3); large text (≥18pt regular / ≥14pt bold) and graphical elements like chart marks and UI components need only ≥3:1 (SC 1.4.11). KPI headlines in the 48-60pt range qualify as large text, while 12-14pt axis labels are body text and need the full 4.5:1. Dark text on light background is always safe. Colored backgrounds need testing (WebAIM Contrast Checker).

### Screen Reader Considerations

- **Chart titles and labels** — Required; screen readers announce titles and axis labels for context.
- **Table headers** — Properly marked so screen readers announce column names.
- **Alt text** — For embedded images or logos, describe content: "Company branding logo".
- **Avoid color-only encoding** — Red means "problem", green means "good"? Also use text labels or icons so color-blind users understand.

### Label Clarity

- **Every axis and legend** must be clearly labeled. Don't assume users know "MTD" or "YTD"; spell out or use tooltips.
- **Measurement units** — "Sales (Millions)" not just "Sales". Include units in data labels where relevant.
- **Calculation conditions** — When object is hidden due to condition, display message: "Select Year to view this chart" instead of blank space.

---

## Section 7: Reference App Pattern Reverse-Engineering

To replicate design patterns from existing Qlik apps, systematically examine sheet structure, object types, filter strategy, colors, layout, and responsive behavior. Document findings in a pattern catalog for reuse in new projects.

**See `references/reference-app-patterns.md` for the detailed 9-step reverse-engineering procedure, pattern catalog template, and replication checklist.**

---

## Section 8: Dashboard Bundle Controls

The Dashboard Bundle ships native-feeling controls (Variable Input, Date Picker, On-Demand Reports, etc.) that integrate via expressions and variables rather than direct field references.

### Variable Input — Dynamic values takes a pipe-delimited string, not a field

The Variable Input control's **Dynamic values** mode parses either value-only pairs separated by pipes (`v1|v2|...`) or value-label pairs (tilde between value and label, pipe between pairs: `v1~L1|v2~L2|...`) and tokenizes it into dropdown options. A bare field reference (`=[Table].[Field]`) resolves to a single scalar and the dropdown collapses — the control does NOT enumerate distinct field values for you.

For small fixed lists, the control's **Static values** mode (configured as individual property-pane rows, not a pipe-delimited string) is simpler; reserve the Dynamic values pipe pattern for data-driven lists where the value set comes from script-time computation.

- **Avoid:** `=[MeasuresMenu].[%MeasureLabel]` and similar bare field references in Dynamic values.
- **Prefer:** materialize the pipe string in the load script (Concat-and-Peek), then reference the resulting variable: `='$(vPipeMeasures)'`.

For the full walkthrough — load-script build, value-label vs value-only form, chart-side double-dollar expansion (`$($(vVar))`), and the slower inline-Concat alternative — see [references/variable-input-control.md](references/variable-input-control.md). The script-side Concat-and-Peek technique is documented in `qlik-load-script` Section 7.

Reference: help.qlik.com Cloud → Dashboard Bundle → Variable Input control.

Reference: help.qlik.com Cloud → Visualization Bundle (https://help.qlik.com/en-US/cloud-services/Subsystems/Hub/Content/Sense_Hub/Visualizations/visualization-bundle.htm).

---

## Cross-References

- **Expression authoring** — See qlik-expressions skill (measures, calculated dimensions, set analysis)
- **Naming conventions** — See qlik-naming-conventions skill (sheet names, object names, field names)
- **Data modeling** — See qlik-data-modeling skill (dimensions, facts, key relationships)
