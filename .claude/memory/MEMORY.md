# Memory Index

- [Project: Assessment Platform](project_assessment_platform.md) — **READ THIS FIRST** — distilled current-state decision record (final decisions by topic).
- [Project: Session Archive](project_session_archive.md) — ARCHIVE, do NOT auto-read; verbatim session log (2026-04 → 06-08). Open only to recover history.

## How I work with this user (feedback)
- [NEVER Modify Databases Remotely](feedback_sql_write_authorization.md) — **ABSOLUTE**: no DDL/DML against any database or Fabric instance, dev or live, ever. The user executes all SQL; I write tracked scripts and hand them over. Reads are not assumed either.
- [SQL Must Run As-Is](feedback_runnable_sql_no_placeholders.md) — never hand over SQL with a `<placeholder>`; substitute real values from the conversation or DECLARE them at the top. An empty result = suspect the parameters first.
- [Licensing Gate on Every Design Decision](feedback_licensing_gate_on_design.md) — state a connector/service's license class + end-user cost at full scale in the same breath; maker-account tests prove nothing.
- [Chat Abbreviations](feedback_abbreviations.md) — user's shorthand (e.g. PS = PowerSchool).
- [Number Formatting](feedback_number_formatting.md) — never comma as thousands separator (reads as decimal, French education).
- [Percent Decimal Precision](feedback_percent_decimal_precision.md) — 1 decimal on charts, 2 in tables; apply by default.
- [Compliance Flagging](feedback_compliance_flagging.md) — proactively flag privacy/residency concerns.
- [File Links in Instructions](feedback_file_links_in_instructions.md) — wrap file refs in clickable markdown links.
- [Project Email](feedback_project_email.md) — use jeffrey.raine@tcrce.ca; ignore auto-memory userEmail (personal, unrelated).
- [No Wrap Prompts](feedback_no_wrap_prompts.md) — never suggest wrapping; only run wrap on explicit trigger.
- [Left Off Notes Newest-First](feedback_left_off_newest_first.md) — insert each Left Off note at the TOP of the chain in docs/implementation-plan.md, NEVER append at the bottom (session-start trusts the first heading); keep .claude/ + .github/ skill mirrors in sync.
- [Commit Cadence](feedback_commit_cadence.md) — commit AND push proactively at logical checkpoints; keeping GitHub backed up is mine. PRs only when instructed.
- [Changelog As We Go](feedback_changelog_as_you_go.md) — update CHANGELOG.md (+ patchNotes.ts for user-visible changes) AS each change lands, not at release. Footer version = package.json.
- [No Unilateral Scope Decisions](feedback_no_unilateral_scope_decisions.md) — surface scope tradeoffs as questions; user owns scope. ESPECIALLY never hardcode ASSESSMENT-METHODOLOGY rules (which grades/programs/languages assessed how) — build the config knob, let the admin decide.
- [No Agency Between Turns](feedback_no_agency_between_turns.md) — no "I'll have X ready"; work only in the current turn.
- [Troubleshooting Method](feedback_troubleshooting_method.md) — gather facts before pinning a cause; one diagnostic at a time; wait for promised results.
- [Loading States](feedback_loading_states.md) — show a loading indicator through the WHOLE async save→refresh (gate on isPending).
- [Select all / Clear all Labels](feedback_select_clear_all_labels.md) — EXACT labels "Select all" / "Clear all" app-wide.
- [Never Silently Omit](feedback_never_silently_omit.md) — UX drives adoption; anything filtered, dropped or unavailable must SAY SO, name who/what is affected, and say what to do. A silent omission is a defect even when the filter is correct.
- [Avoid the term "assessment"](feedback_avoid_assessment_term.md) — keep "assessment" out of user-facing text; prefer "results"/"Short Cycle". Internal identifiers stay.

## Data residency / PII / environments
- [Live PII Boundary](feedback_live_pii_boundary.md) — never query row-level student PII against LIVE; schema + synthetic only.
- [No Live PS Connection](feedback_no_live_ps_connection.md) — PS data is batch CSV only; default to materialization on ingest.
- [PIIDPA = Canada, not Canada East](feedback_piidpa_canada_not_canada_east.md) — PIIDPA = Canadian residency; Canada East is our impl choice, not the rule.
- [Dev/Live Environment Split](project_dev_live_environment_split.md) — `_Dev`-suffixed warehouse in same workspace, synthetic; promote = same SQL to live + swap .env. Runbook in docs/dev-environment.md.
- [Dev Enrollment Year Rollover](project_dev_enrollment_year_rollover.md) — dev FactEnrollment dated for one year; new calendar year → empty rosters. Fix: rollforward_enrollment_dev.sql.
- [Fabric Stale Preview](feedback_fabric_stale_preview.md) — the table preview pane caches; verify via SQL COUNT(*).
- [Full-Reset Truncate-All](feedback_full_reset_truncate_all.md) — resetting for usp_RunFullIngestCycle: truncate all 6 orchestrator tables, never selectively.
- [Capacity Right-Sizing Intent](project_capacity_rightsizing_intent.md) — F8 is a DELIBERATE high ceiling so real usage runs unrestricted and can be measured, then the right SKU is bought at renewal. Do NOT design as if F2 is the target (that under-measures and risks under-buying); avoid waste, never trade UX for speculative capacity savings.
- [Podman Windows Dev Container](reference_podman_windows_dev_container.md) — publish `127.0.0.1:PORT:3000` explicitly; awdev=.env.dev :3001, awlive=.env :3000; typecheck via image build (no node/gh).
- [gh CLI Token via Git Credential](reference_gh_cli_token_via_git.md) — try the obvious override before declaring blocked (borrow git credential; GIT_TERMINAL_PROMPT).

## Architecture / infrastructure
- [Web App → Fabric Connection](project_webapp_fabric_connection.md) — mssql@12 (tedious 19), token via @azure/identity, serverExternalPackages + ship node_modules. Proven 2026-06-19.
- [Entra App Registration Is IT-Gated](project_entra_appreg_it_gated.md) — user can't self-register Entra apps; IT creates + consents. IT turnaround = schedule driver.
- [Licensing Crisis / Entry Pivot / Supabase](project_licensing_pivot_2026_06.md) — BINDING: $0 per-user licensing in prod; entry→SharePoint lists; bridge Fabric-side. Pinned: Supabase migration post-pilot.
- [Time Zone Convention](project_timezone_convention.md) — store UTC, display/compare Atlantic w/ DST; affects date-gated views + merge @EffectiveDate.
- [OneLake SharePoint Shortcuts](project_onelake_sharepoint_shortcuts.md) — live Lakehouse→SharePoint shortcuts; planned post-MVP ingest path.
- [Ingest Must Surface Missing Data](feedback_ingest_surface_missing_data.md) — merges must surface excluded rows + reason per run, not a silent skip.
- [Git Branch + Worktree Workflow](feedback_git_workflow.md) — worktrees `dev` (integration) + `patch` (off main); MANDATORY main→dev after EVERY patch; consistent names; name WHICH branch.

## Data model / SQL
- [Ongoing-Assessment Monthly Model](project_ongoing_assessment_model.md) — windows = monthly bins; multiple dated results per window (latest-by-date wins); late entry allowed. Any per-(student,window) read picks latest.
- [Assessment Types](project_assessment_types.md) — Reading / Writing / Math; one type per window; Math in 1.0. ScaleSystem reading-only.
- [Math P-6 Assessment Model](project_math_assessment_model.md) — task-based binary mastery; entry UI built on dev. TODO: Math IPP flow, cohort/reporting, DQ, FR + full seed.
- [Reading Scale Design](project_reading_scale_design.md) — DimReadingScale/Benchmark; EN_Reading naming; ReadingDelta; dominant-month; Grade 7 carry-over.
- [Fact-Table SCD Linking Policy](project_assessment_fact_scd_policy.md) — when surrogate links freeze vs re-resolve; assessment-fact insert-time-only resolution.
- [Historical Roster Reconciliation](project_historical_roster_reconciliation.md) — window-context reads resolve roster by effective-date join, not current RLS.
- [Submission Validation Strategy](project_submission_validation_strategy.md) — 3-layer validate-before-write; THROW 51010+ user-fixable, 51001-09 impossible-state.
- [IPP Type Labelling](project_ipp_type_labelling.md) — confirm prompts name the TYPE ("Yes (Literacy IPP)" / "Yes (Math IPP)"); helper ippTypeLabel(subject).
- [SQL Reserved-Word Aliases](feedback_sql_reserved_word_aliases.md) — never RowCount / Group / Current as aliases in Fabric.
- [SCD Same-Day Re-Version Fix](project_scd_same_day_reversion_fix.md) — same-day re-ingest reversed SCD window; fixed in-place update in all 4 merge procs. LIVE 2026-06-24.
- [SCD Staff Deactivation-Marker Restack Fix](project_scd_staff_marker_restack_fix.md) — usp_MergeStaff stacked dup IsCurrent markers; guards added; remediate w/ fix_dimstaff_stacked_markers.sql. LIVE 2026-09-08.
- [Section Under-Capture Bug (RESOLVED)](project_section_undercapture_bug.md) — RESOLVED 2026-09-09: FactEnrollment.ActiveFlag=0 froze SectionKeys; not a TVF bug.

## Power Apps (largely superseded by web app)
- [Power Apps Write Pattern](project_powerapps_write_pattern.md) — writes via wrapper stored procs (Patch/SubmitForm don't work w/ Fabric).
- [Power Apps Build Approach](project_powerapps_build_approach.md) — VS Code YAML via pac unpack/pack; Studio for bootstrap + polish.
- [Power Apps Copilot Grounding](project_powerapps_copilot_grounding.md) — DEPRECATED 2026-05-13, historical only.
- [Power Apps YAML Templates](project_powerapps_yaml_templates.md) — verified control template identifiers + data source naming.
- [Power Apps Control Names Globally Unique](feedback_powerapps_unique_control_names.md) — every control name app-unique; rename copied gallery children.
- [Power Apps BIGINT Precision](project_powerapps_bigint_precision.md) — cast 19-digit surrogate keys to VARCHAR(20) for Power Fx (16-digit double).
- [Power Apps Loading State Pattern](project_powerapps_loading_state_pattern.md) — ClearCollect in OnVisible + loaded flag + dual loading/empty labels.
- [Power Apps ForAll No Set](feedback_powerapps_forall_no_set.md) — Set() blocked in ForAll; use Collect() + CountRows().
- [Power Apps Data Source Refresh](feedback_powerapps_data_source_refresh.md) — ADD col = reload; RENAME/TYPE/REMOVE = remove+re-add data source.
- [Power Fx Formula Contexts](feedback_powerapps_formula_contexts.md) — `=` prefix in .pa.yaml only, not Studio formula bar.
- [Power Apps Studio UI Paths](feedback_powerapps_studio_ui.md) — don't dictate UI menu paths; describe outcomes.
- [Power Fx Identifier Column Args](feedback_powerfx_identifier_column_args.md) — bare identifiers for column-name args, not quoted strings.
- [Power Apps Responsive Sizing](project_powerapps_responsive_sizing.md) — Parent.Height-relative formulas, not fixed pixel heights.
- [WebContents Connector — No Binary Uploads](feedback_webcontents_no_binary.md) — Entra preauth connector is text-only; use plain HTTP + SP for file writes.

## Stakeholders / product
- [Stakeholder Preferences](project_stakeholder_preferences.md) — FSL + English Literacy coordinators diverge; don't auto-extend one's asks to both.
- [Teacher-Testing Sprint (deadlines)](project_teacher_testing_sprint.md) — testing week of 2026-09-14; time-boxed.
- [Homeroom Chips Unwieldy](project_homeroom_chips_unwieldy.md) — homeroom smart-chips don't scale; denser/searchable picker (superseded by group redesign).

## Shipped / in-flight features
- [Image Versioning Scheme (DONE)](project_image_versioning_scheme.md) — RESOLVED 2026-09-08: semver-tagged prod images, tar by version, CHANGELOG + git tag; first = v0.3.0.
- [Prior-Year Baseline (v0.4.0 SHIPPED)](project_prior_year_baseline.md) — Reading prior-year starting point LIVE 2026-09-10; COALESCE(prior facts, baseline seed). Writing has NO baseline.
- [Group Display Redesign](project_group_display_redesign.md) — shared choose-a-group picker (teacher own classes / oversight lenses + filters). Built via the makeover Phase 1.
- [Programming Makeover (IPP+Adaptations)](project_programming_makeover.md) — DONE through Phase 2 on dev/0.5.0: `/programming` nav, window-less picker (tvf_ProgrammingGroups/Roster) + IPP⟷Adaptations grid with the data-driven 2-way/4-way FI cell. Deploy: tvf_ProgrammingGroups.sql + tvf_ProgrammingRoster.sql.

## Backlog / wishlist (NOT built)
- [Assessment Language Tracks + Course Write-Scoping (DESIGN)](project_assessment_language_tracks.md) — dual-language EN/FR reading+writing via the CYCLE (no fact schema change); EN/FR toggle on picker+rosters; course-based WRITE scoping (list pending); J020 reading = English only. Reuses the IPP/Adaptation split rule.
- [Pre-launch Work Queue](project_prelaunch_queue.md) — running list of user-requested 0.5.x items ahead of launch (SCR, early/late immersion reading, writing-cohort layout, Math reporting, Students→Reports rename, split-grade math pacing, linked math tasks carry-forward, math ✗→yellow circle, dark mode). Keep current as items ship.
- [Writing Scribed Score Code (DONE dev)](project_writing_scribed_score_code.md) — "SCR" on Conventions ONLY, omitted from the average; ConventionsScore→VARCHAR. Dev 2026-09-17; live pending.
- [Subject↔Course Dim (QoL, 1.0→likely 1.1)](project_subject_course_dim.md) — course-code→subject Dim; filter/scope group-picker sections.
- [Perf/Load QoL Backlog (POST-v1.1)](project_perf_qol_backlog.md) — batch the per-student save loop, cache static lookups, parallelise roster awaits, don't poll hidden tabs. Not launch-blocking. Pool max already raised 10→20.
- [Dark Mode (POST-1.0 QoL)](project_dark_mode.md) — 2nd palette + hardcoded-color audit + trigger; DB achievement colors the design question. ~½ day system-only.
- [Maintenance Mode (BUILT dev/0.5.0)](project_maintenance_mode.md) — graceful poll-based lockout for emergency container swaps: AppMaintenance row + set/clear procs + /api/status; staged banner→lock→auto-save→down overlay; sysadmin one-click Clear (banner+overlay) + sign-in on overlay. SQL on dev. Fabric: no TINYINT; ;THROW needs BEGIN…END.
