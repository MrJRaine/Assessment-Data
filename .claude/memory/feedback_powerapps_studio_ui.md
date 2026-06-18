---
name: don-t-over-specify-power-apps-studio-ui-paths
description: "The current Power Apps Studio is web-based (make.powerapps.com). Old desktop-Studio menu paths (File → Open, View → Variables, etc.) are out of date. Trust the user's familiarity with their tool; don't dictate UI steps that may be wrong."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 7b63aab4-7b87-41e2-8666-353c4cc562cb
---

**Stop giving Power Apps Studio UI step-by-step navigation instructions** (File → Open, View → Variables, View → Properties, etc.) unless I've verified the path in current docs.

**Why:** User flagged 2026-05-20 that my menu-path instructions are from the **legacy Power Apps Studio Desktop**, which was sunset around 2023-2024. The current Studio is web-based at `make.powerapps.com` and uses different navigation:
- "File" menu is replaced by a backstage / hamburger-style menu in the top-left.
- "View" menu items (Variables, Collections, etc.) live under a different top-level area in the modern Studio.
- "Browse files" workflow for opening local `.msapp` differs from desktop's File → Open dialog.

My training data includes documentation from both eras and I've been blurring them. The user has been opening `.msapp` files successfully throughout the project — they know their tool. I don't.

**How to apply:**
- When describing what to do in Studio, describe the **action and outcome**, not the UI path. Examples:
  - ✅ "Open the dev `.msapp` in Studio, run the app, confirm scrLanding loads and the two buttons navigate."
  - ❌ "File → Open → Browse files → pick the dev `.msapp`."
  - ✅ "Confirm `gblIsAdminOrAnalyst` is set (check Variables panel)."
  - ❌ "Click View → Variables. Locate `gblIsAdminOrAnalyst` in the list."
- If the user asks HOW to do something in Studio, **ask back** or admit uncertainty rather than fabricating a menu path. Modern Studio paths I'm confident on are limited.
- Studio terminology I CAN safely use: "the formula bar", "the Data panel" (left sidebar), "the tree view" (left sidebar), "Insert" (control palette), "Run / Stop" (the ▶ button), "Save" (top-right), "Properties pane" (right sidebar when a control is selected).
- Studio terminology to AVOID without verification: any menu paths like "File →", "View →", "Insert →", "Action →". Backstage navigation has changed multiple times.

**Lesson:** the user is doing the Studio work; I'm doing the YAML editing. The handoff is at the `.msapp` file boundary — I describe what the app should DO and what they should VERIFY. I don't need to (and shouldn't) tell them how to click around.
