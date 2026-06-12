---
name: Compliance Flagging
description: User wants proactive callouts when a tooling decision has privacy/residency implications, even if they've already thought about it
type: feedback
originSessionId: ed9fed8b-1165-41dc-a851-2037c97545dc
---
**Proactively flag compliance, privacy, and data-residency concerns** when a workflow decision has those implications — don't silently execute the user's request and assume they've handled it.

**Why:** User works under PIIDPA (data must stay in Canada East). They're a data professional and have usually already thought about the concern, but explicitly appreciated the second pair of eyes. Confirmed 2026-04-28 when I flagged that reading real student CSVs through Claude Code routes data through Anthropic's API (likely outside Canada East) and suggested anonymization / header-only samples — user said "super impressed" because they had already planned the right approach but valued the redundant check.

User's framing of the principle: **"Better to flag it than having the impossible task of putting the toothpaste back in the tube."** Once regulated data is exposed, that exposure can't be undone — prevention is the only meaningful intervention, so the cost of a redundant flag is negligible compared to the cost of missing a real one.

**How to apply:** When a request would expose regulated data (student PII, staff PII, etc.) to systems outside the compliance boundary, surface the concern with concrete options (e.g. "anonymize first", "drop header + dummy rows", "you read locally and paste excerpts"). Do this even when the user is sophisticated and likely has a plan — the redundancy is the value, not a presumption of ignorance. Keep it brief (one short paragraph), not lecturing.

**Specific failure mode to avoid (slip occurred 2026-04-29):** When troubleshooting a real production file (e.g. a PS export sitting in OneLake), do NOT ask the user to download/copy it locally for me to inspect via Read or PowerShell. The file contains real PII; reading it through Claude routes data through Anthropic's API outside Canada East. Even when the user has dummy versions for format validation, *every PS export in OneLake / production paths should be assumed to contain PII unless explicitly stated otherwise*. Workarounds when stuck:
- Have the user run diagnostics themselves locally (encoding check, line-ending count, column-count count via PowerShell/Notepad++) and paste back the **metadata-only summary** (no row content).
- Ask the PS admin to re-export with specific known-good settings if the format is the issue.
- Have the user create a NEW anonymized dummy that matches the *current production format* (different from the old dummy if format changed) so I can see structure.
- Use a Fabric notebook (run by user) to emit non-PII structural metadata.
