# Visualization Output Templates

Reference templates for the three deliverables a viz design pass typically produces: sheet specifications, master item definitions, and a manual build checklist. Templates assume audience = developer or admin who will build the app from the design.

## Template 1: Sheet Specifications (`viz-specifications.md`)

### Header

```markdown
# Visualization Specifications

**Reference App Deviations:** (List any intentional deviations from a reference app with rationale, or "None — design replicates reference app layout and palette".)
```

### Content structure

**Sheet Inventory Table:**

| Sheet | Title | Audience | Purpose |
|---|---|---|---|
| 1 | Executive Overview | C-suite | High-level KPIs and trends |
| 2 | Sales Detail | Sales managers | Drill-down by region, product, time |

**Navigation Flow:** how users move between sheets, entry points, drill-down patterns.

**Color Palette:** all assigned colors for dimensions and metrics, plus accessibility notes.

**Global Filter Pane:** fields, placement, cardinality-based modes, behavior, interaction with calculation conditions.

**Information Density Notes:** how information is tailored by persona (executive vs analyst vs operational).

### Per-sheet section (repeat for each)

```markdown
## Sheet N: [Title]

**Purpose and Audience:** What question does this sheet answer? Who is the user?

**Layout Grid:**
(Sketch using row/column ranges or proportions of sheet width. Cell counts depend on
the Grid spacing setting — describe positions as proportions or named ranges, not absolute
column numbers.)
```

Example at Grid spacing = Wide:

```
Row 1 (KPI strip):       [Filters ~1/5 width] [spacer] [KPI ~1/4 width] [KPI ~1/4 width]
Row 2-3 (Trend):         [Trend Line Chart ~2/3 width]
Row 4-5 (Comparison):    [Bar Chart ~1/2 width] [Summary Table ~1/2 width]
```

### Per-object spec (repeat for each object on each sheet)

```markdown
**Object N.M: [Name]**
- **Type:** KPI / Bar / Line / Combo / Table / Pivot / Scatter / Map / Treemap / Waterfall
- **Dimension(s):** [Calendar.Month] or [multiple dimensions]
- **Measure(s):** vRevenue, vRevenueTarget (reference expression catalog)
- **Sorting:** Month ascending, or custom order
- **Calculation Condition:** vCalcCondSingleYear or "None" — gates when the object *evaluates* (with a user-facing message when unmet, e.g., "Select a single year")
- **Show Condition:** `=GetSelectedCount(Year)=1` or "None" — gates when the object *renders at all* (object is hidden entirely when unmet)
- **Conditional Formatting:** "Green if > target, Red if < target" or "None"
- **Grid Position:** Row 1, right-side strip (~1/4 of sheet width); adjust if Grid spacing differs
- **Responsive Notes:** "Collapses to list on mobile" or "Remains full width"
```

## Template 2: Master Item Definitions (`master-item-definitions.md`)

### Header

```markdown
# Master Item Definitions

**Format:** Copy these definitions into Qlik Sense manually or via bulk import tool.
**Note:** These are visual/organizational masters only. Data expressions come from the expression catalog.
```

### Master measures section

Per measure:

```markdown
**Measure: [Technical Name]**
- **Label:** [Business-Readable Name]
- **Expression:** `Sum([Sales.Amount])`
- **Description:** Total revenue by selected dimensions
- **Format:** Currency, thousands separator, 0 decimals
- **Tags:** Finance, Core Metrics
- **Usage:** KPI cards, bar charts, line charts
```

### Master dimensions section

Per dimension:

```markdown
**Dimension: [Technical Name]**
- **Field:** [Geography.Region]
- **Label:** [Region]
- **Description:** Sales region for regional analysis
- **Sort Order:** Custom (North, South, East, West) or field value ascending
- **Drill-down Group:** dRegionDrill (leads to dTerritory)
```

### Drill-down groups section

Drill-down dimensions are a separate master item type (not a regular dimension with multiple fields). Create them via Master items → Dimensions → Create new → Drill-down.

```markdown
**Drill-down: [Name]**
- **Level 1:** dRegion (Geography.Region)
- **Level 2:** dTerritory (Geography.Territory)
- **Level 3:** dCity (Geography.City)
```

## Template 3: Manual Build Checklist (`manual-build-checklist.md`)

### Header

```markdown
# Manual Build Checklist

**Objective:** Step-by-step instructions to manually construct Qlik Sense sheets from this specification.
**Prerequisites:** All master items defined, data model loaded, connection to data source verified, expressions from the expression catalog imported.
```

### Per-sheet section (repeat for each)

```markdown
## Sheet N: [Title]

**Prerequisites:**
- [ ] Master measures created: [list]
- [ ] Master dimensions created: [list]
- [ ] All expressions from the catalog available in the app
- [ ] Data model validated (no synthetic keys, row counts verified)

**Layout Preparation:**
1. Create new sheet titled "[Sheet Title]"
2. Set sheet description: "[Purpose for business users]"
3. [Layout-specific setup: filter pane placement, grid sizing, etc.]

**Filter Pane (Row N, columns M–P):**
4. Add filter object at position [Row, Columns]
5. Add fields: [Field 1], [Field 2], [Field 3]
6. Set cardinality-based modes: [Field 1] list mode, [Field 2] search mode
7. Set conditional visibility/calculation condition: [Condition]

**KPI Row (Row N, columns M–P):**
8. Insert KPI object at Row N, columns M–P
   - Measure: [Expression Name]
   - Calculation condition: [If any]
   - Formatting: Currency
   - Conditional color: Green if > target, Red if < target
9. [Repeat for each KPI]

**Charts (Row N, columns M–P):**
10. Insert [Chart Type] at Row N, columns M–P
11. Dimension: [Field Name]
12. Measures: [Expression 1], [Expression 2]
13. Sorting: [Field] ascending/descending
14. Conditional formatting: [If any]
15. Enable legend: [Yes/No]

**Table (Row N, columns M–P):**
16. Insert Table at Row N, columns M–P
    - Dimensions: [Field 1], [Field 2]
    - Measures: [Expression 1], [Expression 2]
    - Calculation condition: `GetSelectedCount([Year])>0`
    - Max rows: 50 (performance)
    - Sortable columns: Enabled

**Responsive Behavior:**
17. Test layout by resizing the browser through narrower widths (Qlik publishes the 480px small-screen threshold; tiered breakpoints are author-defined).
18. Verify KPI cards stack vertically on mobile.
19. Verify the filter pane reduces dimension widths (and exposes a dropdown for overflow dimensions) when sheet space is limited — per Qlik filter pane docs; there is no "hamburger drawer" pattern.
20. Verify trend chart remains readable.

**Validation:**
21. Verify all objects render without error.
22. Verify filter selection triggers calculation conditions.
23. Verify no null/missing values without context.
24. Verify color palette matches organizational standard. Inspect via App settings → Appearance → Theme; for static dimension colors, verify against the master dimension's color expression or `theme.json` `colorMap`.
```

## Expression Gap Reporting

When expression gaps are identified during design, document them in a table appended to the sheet specifications:

```markdown
## Expression Gaps Identified

| Gap ID | Expression Needed | Needed For (Sheet/Object) | Business Context | Priority |
|---|---|---|---|---|
| GAP-001 | Year-over-year growth % | Executive Overview, Object 1.3 | "Show how this year compares to last year" | High |
| GAP-002 | Top 10 customers by revenue | Customer Detail, Object 3.2 | Ranked list for account managers | Medium |
| GAP-003 | Forecast vs Actual variance | Planning Sheet, Object 5.1 | Shows deviation from forecast | High |

### Gap Fill Strategy

Each gap needs an expression authored before the manual build can proceed. Once expressions exist, refresh the visualization design to reference them.
```
