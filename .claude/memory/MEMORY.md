# Memory Index

- [Project: Assessment Platform](project_assessment_platform.md) — **READ THIS FIRST** — current-state decision record.
- [Project: Session Archive](project_session_archive.md) — ARCHIVE, do NOT auto-read; open only to recover history.

## How I work with this user (feedback)
- [No Unverified State Claims](feedback_no_unverified_state_claims.md) — ROOT PATTERN: never say live/fixed/clean/retired without naming the check; exit codes, recall and my own prior messages are not verification.
- [Batch Builds During Review Bursts](feedback_batch_builds.md) — accumulate feedback edits; ONE build cycle when the user says done.
- [Imp Container First](feedback_imp_container_first.md) — when the user tests via impersonation, build `-imp` + relaunch awdev-impersonation FIRST.
- [NEVER Modify Databases Remotely](feedback_sql_write_authorization.md) — **ABSOLUTE**: no DDL/DML/reads against any Fabric instance, dev or live. The user runs all SQL; I hand over tracked scripts.
- [Read Existing Handling First](feedback_consult_entry_semantics_for_reports.md) — before stating/assuming/recording/asking/proposing how data is counted, excluded or coloured, READ how the app already does it (entry grid, report code, ruling memory); entry defines semantics. 3 misses in 48h.
- [RLS Review: Verify Every Role Branch](feedback_rls_review_verify_per_role.md) — check each role's scoping against the documented design across the WHOLE surface; never assert an access claim unverified.
- [SQL Must Run As-Is](feedback_runnable_sql_no_placeholders.md) — no `<placeholder>` in run-now SQL; substitute or DECLARE values. Empty result = suspect the parameters first.
- [Resolve Reference Data From Seeds](feedback_resolve_reference_data_from_seeds.md) — grep the repo's seed files for exact IDs/codes instead of a fuzzy LIKE or asking.
- [Licensing Gate on Every Design Decision](feedback_licensing_gate_on_design.md) — state license class + end-user cost at full scale in the same breath.
- [Chat Abbreviations](feedback_abbreviations.md) — user's shorthand (e.g. PS = PowerSchool).
- [Number Formatting](feedback_number_formatting.md) — never comma as thousands separator.
- [Percent Decimal Precision](feedback_percent_decimal_precision.md) — 1 decimal on charts, 2 in tables; apply by default.
- [Compliance Flagging](feedback_compliance_flagging.md) — proactively flag privacy/residency concerns.
- [File Links in Instructions](feedback_file_links_in_instructions.md) — wrap file refs in clickable markdown links.
- [Project Email](feedback_project_email.md) — use jeffrey.raine@tcrce.ca; ignore auto-memory userEmail.
- [No Wrap Prompts](feedback_no_wrap_prompts.md) — never suggest wrapping; only run wrap on explicit trigger.
- [Left Off Notes Newest-First](feedback_left_off_newest_first.md) — insert each Left Off note at the TOP of the chain in docs/implementation-plan.md; keep .claude/ + .github/ skill mirrors in sync.
- [Entra-Only Auth (dev + live)](feedback_entra_only_auth.md) — dev/main have NO dev-auth bypass; it lives ONLY on dev-impersonation — revert the removal commit there on each dev merge.
- [Commit Cadence](feedback_commit_cadence.md) — commit AND push at logical checkpoints (incl. `dev-impersonation` on every reconcile); PRs only when instructed; the release ritual fires automatically on a successful LIVE deploy and ALSO updates the live/previous version in `docs/prod-container-swap.md` (the DR runbook).
- [Changelog As We Go](feedback_changelog_as_you_go.md) — update CHANGELOG.md (+ patchNotes.ts if user-visible) AS each change lands; rules for repairs vs Fixed and for between-release server-side patches are in the file.
- [v1.0.0 Release Changelog](project_v1_release_changelog.md) — TWO surfaces, don't conflate: in-app What's New holds the current release only; CHANGELOG.md keeps full history.
- [No Unilateral Scope Decisions](feedback_no_unilateral_scope_decisions.md) — surface scope tradeoffs as questions; never hardcode ASSESSMENT-METHODOLOGY rules — build the config knob.
- [Implement Exactly / Flag the Cost](feedback_implement_exactly_flag_cost.md) — do the instruction to the letter; never silently substitute a cheaper near-equivalent; SURFACE the cost and let the user choose.
- [No Agency Between Turns](feedback_no_agency_between_turns.md) — no "I'll have X ready"; work only in the current turn.
- [Troubleshooting Method](feedback_troubleshooting_method.md) — gather facts before pinning a cause; one diagnostic at a time; wait for promised results.
- [Don't Report Back Confirmed Facts](feedback_dont_report_back_confirmed_facts.md) — take a user-stated fact as given; verify quietly, don't narrate it, never call it "good news."
- [Fix vs Workaround](feedback_fix_vs_workaround.md) — "fix" = root cause identified AND resolved; otherwise call it a WORKAROUND and say the root cause is open.
- [Keep Memories Current](feedback_keep_memories_current.md) — update/DELETE a memory at its source the moment its item ships or reverses; one source of truth.
- [Idempotent Deploy Bundles](feedback_idempotent_deploy_bundles.md) — before hand-over: every object idempotent, SEAM-AUDIT (every DROP preceded by GO), and check every object the bundle READS exists on the target (live is NOT the git tag).
- [Loading States](feedback_loading_states.md) — show a loading indicator through the WHOLE async save→refresh (gate on isPending).
- [Select all / Clear all Labels](feedback_select_clear_all_labels.md) — EXACT labels "Select all" / "Clear all" app-wide.
- [Never Silently Omit](feedback_never_silently_omit.md) — anything filtered, dropped or unavailable must SAY SO, name who is affected, and say what to do.
- [Avoid the term "assessment"](feedback_avoid_assessment_term.md) — keep "assessment" out of user-facing text; prefer "results"/"Short Cycle".
- [Say "expanded roster view"](feedback_expanded_roster_view_term.md) — user-facing text + public change log say "expanded roster view", never "drill"/"drill-down".

## Data residency / PII / environments
- [Live PII Boundary](feedback_live_pii_boundary.md) — never query row-level STUDENT PII against LIVE; schema + synthetic only. Staff name + work email are not PII.
- [No Live PS Connection](feedback_no_live_ps_connection.md) — PS data is batch CSV only; default to materialization on ingest.
- [PIIDPA = Canada, not Canada East](feedback_piidpa_canada_not_canada_east.md) — PIIDPA = Canadian residency; Canada East is our impl choice, not the rule.
- [Dev/Live Environment Split](project_dev_live_environment_split.md) — `_Dev` warehouse in the same workspace, synthetic; dev is always AHEAD; promote via the semver `sql/deploy/live_X.Y.Z/` bundles.
- [Dev Enrollment Year Rollover](project_dev_enrollment_year_rollover.md) — new calendar year → empty dev rosters; fix: rollforward_enrollment_dev.sql.
- [Fabric Stale Preview](feedback_fabric_stale_preview.md) — the table preview pane caches; verify via SQL COUNT(*).
- [Full-Reset Truncate-All](feedback_full_reset_truncate_all.md) — truncate all 6 orchestrator tables, never selectively.
- [Capacity Right-Sizing Intent](project_capacity_rightsizing_intent.md) — F8 is a DELIBERATE high ceiling to measure real usage before renewal; never trade UX for speculative capacity savings.
- [Load-Test Findings (2026-10)](project_loadtest_findings_2026_10.md) — app is **Fabric-bound**; F8 ceiling ~6-7 RPS; scale via Fabric SKU / cheaper queries, NOT replicas/CPU/pool.
- [Podman Windows Dev Container](reference_podman_windows_dev_container.md) — publish `127.0.0.1:PORT:3000`; awlive :3000, awdev :3001, awdev-impersonation :3002 (`-imp` image); typecheck via image build.
- [gh CLI Token via Git Credential](reference_gh_cli_token_via_git.md) — borrow the git credential before declaring blocked.
- [IT Modifies SPs + COPY INTO Auth](reference_it_modifies_sps_and_copyinto_auth.md) — sign-in/ingest breaks with no code change → check the Entra side FIRST; COPY INTO from OneLake runs via a Workspace-Identity credential workaround.
- [Read .xlsx + Check Logs First](reference_read_xlsx_and_check_logs_first.md) — "we did this before" → search the archive for the ACTUAL method first; .xlsx reads via PowerShell OOXML-unzip; COPY INTO paths keep literal spaces.
- [Dev Generator Cutover Format](reference_dev_generator_cutover_format.md) — ALWAYS run `_generate_ingest_testset.ps1 -Format Cutover`, EVERY regen; the Legacy default gives a silent 0-row ingest.

## Architecture / infrastructure
- [Web App → Fabric Connection](project_webapp_fabric_connection.md) — mssql@12 + @azure/identity token; serverExternalPackages + ship node_modules.
- [Entra App Registration Is IT-Gated](project_entra_appreg_it_gated.md) — IT creates + consents; IT turnaround = schedule driver.
- [Licensing Crisis / Entry Pivot / Supabase](project_licensing_pivot_2026_06.md) — BINDING: $0 per-user licensing; entry→SharePoint lists; Supabase migration pinned post-pilot.
- [Time Zone Convention](project_timezone_convention.md) — store UTC, display/compare Atlantic w/ DST; affects date-gated views + merge @EffectiveDate.
- [OneLake SharePoint Shortcuts](project_onelake_sharepoint_shortcuts.md) — live Lakehouse→SharePoint shortcuts; planned post-MVP ingest path.
- [Ingest Must Surface Missing Data](feedback_ingest_surface_missing_data.md) — merges must surface excluded rows + reason per run, not a silent skip.
- [Git Branch + Worktree Workflow](feedback_git_workflow.md) — worktrees `dev` + `patch` (off main); MANDATORY main→dev after EVERY patch; name WHICH branch.

## Data model / SQL
- [Ongoing-Assessment Monthly Model](project_ongoing_assessment_model.md) — windows = monthly bins; latest-by-date result wins; late entry allowed.
- [Reports "Current" = Lifetime](project_current_mode_semantics.md) — "Current" = each student's most recent evidence on record (any year); NEVER add a school-year gate; IPP/unresolved get NO achievement band. Math/RWM-math stay current-year.
- [Assessment Types](project_assessment_types.md) — Reading / Writing / Math; one type per window; Math in 1.0. ScaleSystem reading-only.
- [Math IPP Display Rules](project_math_ipp_display_rules.md) — RULED 2026-11-17: uniform 80%-of-ALL-tasks threshold; earned levels count everywhere; below threshold = IPP badge; unresolved = unmeasured.
- [Math P-6 Assessment Model](project_math_assessment_model.md) — task-based binary mastery; open TODOs in the file.
- [Math Split-Grade Pacing Model](project_math_split_pacing_model.md) — BUILD IN PROGRESS (1.5.0 main feature): split = HOMEROOM grade set per school (one student counts); regional guide by grade combination + teacher overrides in their own table; READ the 2026-11-19 rulings + build log before touching it.
- [Math Report Blank-Roster Bug](project_math_report_blank_roster_bug.md) — grades with no seeded math tasks drop the whole class; app-side fix DEFERRED (user call), don't re-propose.
- [Math Task Month Mis-coding](project_math_task_month_miscoding.md) — SCoR months = 9,11,1,3,4,6; Math team mis-codes Feb/May for Jan/Apr → fix at CONVERSION time, before ingest.
- [User-Authored Data Is Auditable](project_user_authored_is_auditable.md) — anything a user authors/edits tracks WHO created, changed or removed it. TODO: extend to maintenance/ingest/cycles ops.
- [Reading Scale Design](project_reading_scale_design.md) — DimReadingScale/Benchmark, ReadingDelta, dominant-month, Grade 7 carry-over.
- [Fact-Table SCD Linking Policy](project_assessment_fact_scd_policy.md) — facts carry stable StudentNumber; reads match the current student by StudentNumber, NOT the mutable StudentKey (LIVE 2026-10-13).
- [Historical Roster Reconciliation](project_historical_roster_reconciliation.md) — window-context reads resolve roster AND displayed teacher as-of the cycle; "admin current-only" is about ACCESS scope only.
- [Submission Validation Strategy](project_submission_validation_strategy.md) — 3-layer validate-before-write; THROW 51010+ user-fixable, 51001-09 impossible-state.
- [IPP Type Labelling](project_ipp_type_labelling.md) — confirm prompts name the TYPE ("Yes (Literacy IPP)" / "Yes (Math IPP)").
- [SQL Reserved-Word Aliases](feedback_sql_reserved_word_aliases.md) — never RowCount / Group / Current as aliases in Fabric.
- [SCD Same-Day Re-Version Fix](project_scd_same_day_reversion_fix.md) — same-day re-ingest reversed the SCD window; fixed in all 4 merge procs. LIVE 2026-06-24.
- [SCD Staff Deactivation-Marker Restack Fix](project_scd_staff_marker_restack_fix.md) — usp_MergeStaff stacked duplicate IsCurrent markers; guards added. LIVE 2026-09-08.
- [Section Under-Capture Bug (RESOLVED)](project_section_undercapture_bug.md) — RESOLVED 2026-09-09: ActiveFlag=0 froze SectionKeys; not a TVF bug.

## Power Apps (largely superseded by web app)
- [Power Apps Write Pattern](project_powerapps_write_pattern.md) — writes via wrapper stored procs.
- [Power Apps Build Approach](project_powerapps_build_approach.md) — YAML via pac unpack/pack; Studio for polish.
- [Power Apps Copilot Grounding](project_powerapps_copilot_grounding.md) — DEPRECATED 2026-05-13, historical only.
- [Power Apps YAML Templates](project_powerapps_yaml_templates.md) — verified control template identifiers.
- [Power Apps Control Names Globally Unique](feedback_powerapps_unique_control_names.md) — every control name app-unique.
- [Power Apps BIGINT Precision](project_powerapps_bigint_precision.md) — cast 19-digit keys to VARCHAR(20).
- [Power Apps Loading State Pattern](project_powerapps_loading_state_pattern.md) — ClearCollect in OnVisible + loaded flag.
- [Power Apps ForAll No Set](feedback_powerapps_forall_no_set.md) — Set() blocked in ForAll; use Collect() + CountRows().
- [Power Apps Data Source Refresh](feedback_powerapps_data_source_refresh.md) — ADD col = reload; other changes = remove + re-add.
- [Power Fx Formula Contexts](feedback_powerapps_formula_contexts.md) — `=` prefix in .pa.yaml only, not Studio formula bar.
- [Power Apps Studio UI Paths](feedback_powerapps_studio_ui.md) — don't dictate UI menu paths; describe outcomes.
- [Power Fx Identifier Column Args](feedback_powerfx_identifier_column_args.md) — bare identifiers for column-name args, not quoted strings.
- [Power Apps Responsive Sizing](project_powerapps_responsive_sizing.md) — Parent.Height-relative formulas.
- [WebContents Connector — No Binary Uploads](feedback_webcontents_no_binary.md) — text-only; plain HTTP + SP for files.

## Stakeholders / product
- [Stakeholder Preferences](project_stakeholder_preferences.md) — FSL + English Literacy coordinators diverge; don't auto-extend one's asks to both.
- [Teacher-Testing Sprint (deadlines)](project_teacher_testing_sprint.md) — testing week of 2026-09-14; time-boxed.
- [Grace Period Hidden From Teachers](project_grace_period_hidden_from_teachers.md) — the post-close grace window stays OUT of all teacher-facing comms, by design.
- [Homeroom Chips Unwieldy](project_homeroom_chips_unwieldy.md) — superseded by the group redesign.

## Shipped / in-flight features
- [Writing Trait Exclusion (v1.0.0 LIVE)](project_writing_trait_exclusion.md) — data-driven `WritingTraitExclusion`; excluded trait stored as `-` (not NULL), dropped from averages; traits are VARCHAR.
- [Roster Materialization (0.6.2 LIVE)](project_roster_materialization.md) — membership tables in LOCKSTEP with the roster TVFs; section-stable rebuild LIVE 2026-10-13 (SectionID + StudentNumber); TEACHER-axis version still OPEN.
- [Image Versioning Scheme (DONE)](project_image_versioning_scheme.md) — semver-tagged prod images, tar by version, CHANGELOG + git tag.
- [Prior-Year Baseline (v0.4.0 SHIPPED)](project_prior_year_baseline.md) — Reading prior-year starting point LIVE 2026-09-10; Writing has NO baseline.
- [Group Display Redesign](project_group_display_redesign.md) — shared choose-a-group picker; built via the makeover Phase 1.
- [Programming Makeover (IPP+Adaptations)](project_programming_makeover.md) — DONE through Phase 2 on dev/0.5.0: `/programming` nav, window-less picker + IPP⟷Adaptations grid.
- [Assessment Language Tracks + Course Write-Scoping](project_assessment_language_tracks.md) — dual-language EN/FR reading+writing via the CYCLE; course-based WRITE scoping; J020 reading = English only.
- [Writing Scribed Score Code](project_writing_scribed_score_code.md) — "SCR" on Conventions ONLY, omitted from the average. Dev 2026-09-17; live pending.
- [Maintenance Mode (BUILT dev/0.5.0)](project_maintenance_mode.md) — poll-based staged lockout for emergency container swaps (AppMaintenance row, set/clear procs, /api/status).

## Backlog / wishlist (NOT built)
- [Feature Ideas & Backlog](project_feature_ideas_and_backlog.md) — triaged queue of unbuilt work; prune as items ship.
- [Subject↔Course Dim (QoL)](project_subject_course_dim.md) — course-code→subject Dim; filter/scope group-picker sections.
- [Perf/Load QoL Backlog (POST-v1.1)](project_perf_qol_backlog.md) — batch saves, cache static lookups, parallelise roster awaits, don't poll hidden tabs.
- [Dark Mode (POST-1.0 QoL)](project_dark_mode.md) — 2nd palette + hardcoded-color audit; DB achievement colors are the design question.
