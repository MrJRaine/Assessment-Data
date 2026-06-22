---
name: project_ipp_type_labelling
description: "IPP confirmation prompts label the IPP TYPE (Literacy / Math), never bare \"IPP\" — the student's IPP existence is already known; the gate confirms which type."
metadata: 
  node_type: memory
  type: project
  originSessionId: cc5fc7f0-3ff9-4368-a158-ef0c6bf09cbb
---

The IPP needs-confirmation gate is NOT asking "does this student have an IPP?" — by the time a NULL-gate row exists we already know PS flagged them (`DimStudent.IPP = 1`). The gate confirms **which type** of IPP. So confirm-prompt button labels name the type, not a bare "IPP":

- **Reading** and **Writing** → **"Yes (Literacy IPP)"** (both subjects roll up to one "Literacy" label for teachers).
- **Math** (post-MVP) → **"Yes (Math IPP)"**.

Implemented as `ippTypeLabel(subject)` in `webapp/src/app/enter/[windowId]/[groupKey]/RosterEntry.tsx` (`subject === 'Math' ? 'Math IPP' : 'Literacy IPP'`). Reuse the same helper on the future dedicated IPP-management screen (`/ipp`, mirrors Power App `scrIPP`) and any Writing/Math entry screens.

Note the model/UI tension to keep in mind: `FactStudentIPP` stores **separate Reading and Writing rows** (a student can have a Reading IPP but not Writing), but the UI label groups them as "Literacy". The label is a teacher-facing simplification; the underlying per-subject rows stay distinct. See [[project_reading_scale_design]] (vendor-neutral "Literacy"/no-F&P naming) and [[project_assessment_types]] (Reading/Writing/Math; Math post-MVP).
