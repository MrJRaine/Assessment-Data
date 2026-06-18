---
name: percent-decimal-precision
description: "Percentage values display with different precision depending on the surface: 1 decimal place on graphs/charts, 2 decimal places in tables / detailed views. Apply this convention by default on any new percent-displaying control."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2132ef2f-c5ac-4703-9c69-7138263cb7d1
---

When formatting percentages in this app's Power Apps surfaces:

| Surface | Format | Example |
|---|---|---|
| Charts & graphs (pie slice labels, bar tooltips, etc.) | **1 decimal** | `33.3%`, `11.1%`, `0.0%` |
| Tables, gallery cells, detail rows | **2 decimals** | `33.33%`, `11.11%`, `0.00%` |

**Power Fx formula form:**

```
// Charts: 1 decimal
Text(value, "0.0") & "%"

// Tables: 2 decimals
Text(value, "0.00") & "%"
```

Use `Text(..., "0.0")` rather than `Round(..., 1)` — `Round` returns a number that displays without trailing zeros (33.0 → "33"), while `Text` with `"0.0"` format string forces the decimal place to render regardless.

**Why:** Two-decimal precision is appropriate where users can read carefully (a small data table on a detail screen). On charts/graphs the labels are scanned at a glance, so one decimal is clearer and reduces visual clutter — anchored 2026-05-28 during scrStudentData pie chart label work.

**How to apply:** Any time I write a Power Fx formula that produces a percentage display, choose the format string by surface type. No need to ask the user for this preference each time — it's standing convention.

Related: [[feedback_number_formatting]] — don't use comma as thousands separator in this user's locale.
