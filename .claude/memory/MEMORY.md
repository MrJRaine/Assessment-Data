# Memory Index

- [Project: Assessment Platform](project_assessment_platform.md) â€” **READ THIS FIRST** â€” distilled current-state decision record (final decisions by topic).
- [Project: Session Archive](project_session_archive.md) â€” ARCHIVE, do NOT auto-read; verbatim session log (2026-04 â†’ 06-08). Open only to recover history.

## How I work with this user (feedback)
- [Batch Builds During Review Bursts](feedback_batch_builds.md) â€” don't rebuild/relaunch/commit after every bullet of feedback; accumulate edits and do ONE build cycle when the user says done.
- [Imp Container First](feedback_imp_container_first.md) â€” when the user is testing via impersonation, build `-imp` + relaunch awdev-impersonation FIRST (it's what they view); awdev (:3001) after or skip.
- [NEVER Modify Databases Remotely](feedback_sql_write_authorization.md) â€” **ABSOLUTE**: no DDL/DML/reads against any database or Fabric instance, dev or live, ever. The user executes all SQL; I write tracked scripts and hand them over.
- [Consult Entry Semantics for Reports](feedback_consult_entry_semantics_for_reports.md) — the data-entry surface DEFINES what stored values mean; report changes mirror it or escalate the divergence, never redesign from a cross-subject analogy.
- [RLS Review: Verify Every Role Branch](feedback_rls_review_verify_per_role.md) â€” check each role's scoping against the documented design (DimRole/StaffSchoolAccess) across the WHOLE surface; a region-wide branch is a red flag; never assert an access claim unverified or double down when challenged.
- [SQL Must Run As-Is](feedback_runnable_sql_no_placeholders.md) â€” never hand over run-now SQL with a `<placeholder>`; substitute real values or DECLARE them at the top. An empty result = suspect the parameters first.
- [Resolve Reference Data From Seeds](feedback_resolve_reference_data_from_seeds.md) â€” grep the repo's seed files (DimSchool/DimProgram/DimRole) to resolve namesâ†’exact IDs/codes locally instead of a fuzzy LIKE or asking; it's in my lane.
- [Licensing Gate on Every Design Decision](feedback_licensing_gate_on_design.md) â€” state a connector/service's license class + end-user cost at full scale in the same breath; maker-account tests prove nothing.
- [Chat Abbreviations](feedback_abbreviations.md) â€” user's shorthand (e.g. PS = PowerSchool).
- [Number Formatting](feedback_number_formatting.md) â€” never comma as thousands separator (reads as decimal, French education).
- [Percent Decimal Precision](feedback_percent_decimal_precision.md) â€” 1 decimal on charts, 2 in tables; apply by default.
- [Compliance Flagging](feedback_compliance_flagging.md) â€” proactively flag privacy/residency concerns.
- [File Links in Instructions](feedback_file_links_in_instructions.md) â€” wrap file refs in clickable markdown links.
- [Project Email](feedback_project_email.md) â€” use jeffrey.raine@tcrce.ca; ignore auto-memory userEmail (personal, unrelated).
- [No Wrap Prompts](feedback_no_wrap_prompts.md) â€” never suggest wrapping; only run wrap on explicit trigger.
- [Left Off Notes Newest-First](feedback_left_off_newest_first.md) â€” insert each Left Off note at the TOP of the chain in docs/implementation-plan.md, NEVER append at the bottom (session-start trusts the first heading); keep .claude/ + .github/ skill mirrors in sync.
- [Entra-Only Auth (dev + live)](feedback_entra_only_auth.md) â€” dev/main code has NO dev-auth bypass (AUTH_MODE=dev/DEV_FAKE_UPN removed 2026-10-12); it lives ONLY on dev-impersonation â€” revert the removal commit there on each dev merge. User instruction, previously lost.
- [Commit Cadence](feedback_commit_cadence.md) â€” commit AND push proactively at logical checkpoints; backing up GitHub is mine. PRs only when instructed â€” BUT the full release ritual (devâ†’main, tag vX.Y.Z, gh release, back-merge, reconcile imp) fires automatically on a SUCCESSFUL LIVE DEPLOY, not a separate trigger.
- [Changelog As We Go](feedback_changelog_as_you_go.md) â€” update CHANGELOG.md (+ patchNotes.ts for user-visible changes) AS each change lands, not at release. Footer version = package.json. REPAIRS of things that shipped working then broke (infra/env regressions) go in the internal log only; CHANGELOG Fixed = broken-since-its-own-release defects only. Server-only SQL fixes deployed live between releases = a dated "server-side patch" bullet UNDER THE CURRENT RELEASE (not [Unreleased], NO semver bump/no 1.2.x, no patchNotes).
- [v1.0.0 Release Changelog](project_v1_release_changelog.md) â€” TWO surfaces, DON'T conflate: in-app What's New (`patchNotes.ts`) holds ONLY the current release entry (delete old 0.x/prior, or they SHOW); CHANGELOG.md = bare release line + full history below. "Only the release" â‰  delete prior work from history.
- [No Unilateral Scope Decisions](feedback_no_unilateral_scope_decisions.md) â€” surface scope tradeoffs as questions; user owns scope. ESPECIALLY never hardcode ASSESSMENT-METHODOLOGY rules (which grades/programs/languages assessed how) â€” build the config knob, let the admin decide.
- [Implement Exactly / Flag the Cost](feedback_implement_exactly_flag_cost.md) â€” do the instruction to the letter; NEVER silently substitute a cheaper near-equivalent to dodge a migration/refactor. If it's expensive, SURFACE the cost and let the user choose. (repeated pattern)
- [No Agency Between Turns](feedback_no_agency_between_turns.md) â€” no "I'll have X ready"; work only in the current turn.
- [Troubleshooting Method](feedback_troubleshooting_method.md) â€” gather facts before pinning a cause; one diagnostic at a time; wait for promised results.
- [Don't Report Back Confirmed Facts](feedback_dont_report_back_confirmed_facts.md) â€” when the user states a fact, take it as given; verify quietly for the exact reference but don't narrate that it was confirmed, and never call it "good news."
- [Fix vs Workaround](feedback_fix_vs_workaround.md) â€” "fix" = root cause identified AND resolved; routing around an undiagnosed problem is a WORKAROUND â€” name it that and say the root cause is still open.
- [Keep Memories Current](feedback_keep_memories_current.md) â€” update/DELETE a memory at its source the moment its item ships or reverses; record provenance; one source of truth; prune running lists. Stale notes cause repetitive re-litigation.
- [Idempotent Deploy Bundles](feedback_idempotent_deploy_bundles.md) â€” before handing over a bundled SQL deploy, scan sources so every object is idempotent (DROP-IF-EXISTS + GO, guarded ALTERs, EXEC-wrapped column DML); then SEAM-AUDIT the assembled bundle: every DROP's nearest preceding code line must be GO â€” a statement after a proc's END; without GO compiles SILENTLY into the proc body and executes on every run (caused the 2026-10-30 live math outage). New-table CREATEs are the intentional run-once exception.
- [Loading States](feedback_loading_states.md) â€” show a loading indicator through the WHOLE async saveâ†’refresh (gate on isPending).
- [Select all / Clear all Labels](feedback_select_clear_all_labels.md) â€” EXACT labels "Select all" / "Clear all" app-wide.
- [Never Silently Omit](feedback_never_silently_omit.md) â€” anything filtered, dropped or unavailable must SAY SO, name who/what is affected, and say what to do. A silent omission is a defect even when the filter is correct.
- [Avoid the term "assessment"](feedback_avoid_assessment_term.md) â€” keep "assessment" out of user-facing text; prefer "results"/"Short Cycle". Internal identifiers stay.

## Data residency / PII / environments
- [Live PII Boundary](feedback_live_pii_boundary.md) â€” never query row-level STUDENT PII against LIVE; schema + synthetic only. Staff name + work email are public, NOT PII.
- [No Live PS Connection](feedback_no_live_ps_connection.md) â€” PS data is batch CSV only; default to materialization on ingest.
- [PIIDPA = Canada, not Canada East](feedback_piidpa_canada_not_canada_east.md) â€” PIIDPA = Canadian residency; Canada East is our impl choice, not the rule.
- [Dev/Live Environment Split](project_dev_live_environment_split.md) â€” `_Dev`-suffixed warehouse in same workspace, synthetic; promote = same SQL to live + swap .env. Dev is always AHEAD (dev-first); catch-up only on wipe/revert, via the semver `sql/deploy/live_X.Y.Z/` bundles.
- [Dev Enrollment Year Rollover](project_dev_enrollment_year_rollover.md) â€” dev FactEnrollment dated for one year; new calendar year â†’ empty rosters. Fix: rollforward_enrollment_dev.sql.
- [Fabric Stale Preview](feedback_fabric_stale_preview.md) â€” the table preview pane caches; verify via SQL COUNT(*).
- [Full-Reset Truncate-All](feedback_full_reset_truncate_all.md) â€” resetting for usp_RunFullIngestCycle: truncate all 6 orchestrator tables, never selectively.
- [Capacity Right-Sizing Intent](project_capacity_rightsizing_intent.md) â€” F8 is a DELIBERATE high ceiling so real usage runs unrestricted and can be measured, then the right SKU is bought at renewal. Don't design as if F2 is the target; avoid waste, never trade UX for speculative capacity savings.
- [Load-Test Findings (2026-10)](project_loadtest_findings_2026_10.md) â€” app is **Fabric-bound**, not app/VM/pool-bound. F8 ceiling ~6-7 RPS; pool knee `FABRIC_POOL_MAX=20`; usable latency to ~20 concurrent. Scale via Fabric SKU / cheaper queries, NOT replicas/CPU/pool.
- [Podman Windows Dev Container](reference_podman_windows_dev_container.md) â€” publish `127.0.0.1:PORT:3000` explicitly; THREE containers: awlive=.env :3000, awdev=.env.dev :3001, awdev-impersonation :3002 (`-imp` image, `-e AUTH_MODE=dev`); typecheck via image build.
- [gh CLI Token via Git Credential](reference_gh_cli_token_via_git.md) â€” try the obvious override before declaring blocked (borrow git credential; GIT_TERMINAL_PROMPT).
- [IT Modifies SPs + COPY INTO Auth](reference_it_modifies_sps_and_copyinto_auth.md) â€” when sign-in/ingest breaks and OUR code didn't change that path, check the Entra side FIRST (IT changes app regs/SPs/tenant settings without notice). Fabric COPY INTO from OneLake = caller-passthrough, no Managed Identity (Msg 13838); #1119 closed via a Workspace-Identity CREDENTIAL workaround (root cause unresolved, not pursued).
- [Read .xlsx + Check Logs First](reference_read_xlsx_and_check_logs_first.md) â€” when the user says "we did this before", search the archive/transcripts for the ACTUAL method before reconstructing. E.g. read a `.xlsx` WITHOUT Excel via PowerShell OOXML-unzip â†’ dump to text â†’ Read. COPY INTO path: spaces LITERAL, never `%20`.
- [Dev Generator Cutover Format](reference_dev_generator_cutover_format.md) â€” ALWAYS run `_generate_ingest_testset.ps1 -Format Cutover`; the Legacy default emits `AssessmentData*.text` the loaders' `Students*`/`Enrollments*` globs don't match â†’ silent 0-row COPY INTO (DQ still "passes" on empty). Its clean step wipes the good `.csv` on any default regen, so pass the flag EVERY regen.

## Architecture / infrastructure
- [Web App â†’ Fabric Connection](project_webapp_fabric_connection.md) â€” mssql@12 (tedious 19), token via @azure/identity, serverExternalPackages + ship node_modules. Proven 2026-06-19.
- [Entra App Registration Is IT-Gated](project_entra_appreg_it_gated.md) â€” user can't self-register Entra apps; IT creates + consents. IT turnaround = schedule driver.
- [Licensing Crisis / Entry Pivot / Supabase](project_licensing_pivot_2026_06.md) â€” BINDING: $0 per-user licensing in prod; entryâ†’SharePoint lists; bridge Fabric-side. Pinned: Supabase migration post-pilot.
- [Time Zone Convention](project_timezone_convention.md) â€” store UTC, display/compare Atlantic w/ DST; affects date-gated views + merge @EffectiveDate.
- [OneLake SharePoint Shortcuts](project_onelake_sharepoint_shortcuts.md) â€” live Lakehouseâ†’SharePoint shortcuts; planned post-MVP ingest path.
- [Ingest Must Surface Missing Data](feedback_ingest_surface_missing_data.md) â€” merges must surface excluded rows + reason per run, not a silent skip.
- [Git Branch + Worktree Workflow](feedback_git_workflow.md) â€” worktrees `dev` (integration) + `patch` (off main); MANDATORY mainâ†’dev after EVERY patch; consistent names; name WHICH branch.

## Data model / SQL
- [Ongoing-Assessment Monthly Model](project_ongoing_assessment_model.md) â€” windows = monthly bins; multiple dated results per window (latest-by-date wins); late entry allowed.
- [Reports "Current" = Lifetime](project_current_mode_semantics.md) â€” "Current" on report pages = each student's most recent evidence ON RECORD (any school year); tvf_StudentCohort is the spec â€” NEVER add a school-year gate to a Current-mode latest-pick (population/grade-span gates may stay current-year). IPP/unresolved students get NO achievement band anywhere achievement is aggregated. (Math/RWM-math deliberately stay current-year â€” taskÃ—gradeÃ—month model.)
- [Assessment Types](project_assessment_types.md) â€” Reading / Writing / Math; one type per window; Math in 1.0. ScaleSystem reading-only.
- [Math IPP Display Rules](project_math_ipp_display_rules.md) — RULED 2026-11-17: uniform 80%-of-ALL-tasks threshold (deleted outcomes count the denominator); earned levels count everywhere incl. donut; below threshold = IPP badge not Incomplete; unresolved = unmeasured.
- [Math P-6 Assessment Model](project_math_assessment_model.md) â€” task-based binary mastery; entry UI built on dev. TODO: Math IPP flow, cohort/reporting, DQ, FR + full seed.
- [Math Split-Grade Pacing Model](project_math_split_pacing_model.md) â€” DESIGN 2026-09-21 (not built): default month on task + SCD composition exceptions; carry-forward via edge links; DimHomeroom SCD from ingest. Structural footprint locked.
- [Math Report Blank-Roster Bug](project_math_report_blank_roster_bug.md) â€” grades w/ no seeded math tasks â†’ tvf_StudentCohortMath INNER JOIN Tasks drops the whole class. App-side fix DEFERRED (user call) â€” self-resolves on seeding; don't re-propose. TODO(user): pull latest math tasks from the share doc.
- [Math Task Month Mis-coding](project_math_task_month_miscoding.md) â€” SCoR months = 9,11,1,3,4,6 (Reading benchmark AND Math task-pull). Math team mis-codes SCoR-3/SCoR-5 as Feb(2)/May(5) instead of Jan(1)/Apr(4) â†’ fix the months AT CONVERSION time (before ingest), not a post-seed UPDATE. Math window BenchmarkMonth NULL â†’ dominant-month fallback misses the task month.
- [User-Authored Data Is Auditable](project_user_authored_is_auditable.md) â€” anything a user authors/edits tracks WHO created + who changed/removed it (SCD: created/ended-by per version; Type-1 dims: separate audit log). TODO: extend audit to maintenance/ingest/cycles ops.
- [Reading Scale Design](project_reading_scale_design.md) â€” DimReadingScale/Benchmark; EN_Reading naming; ReadingDelta; dominant-month; Grade 7 carry-over.
- [Fact-Table SCD Linking Policy](project_assessment_fact_scd_policy.md) â€” when surrogate links freeze vs re-resolve; assessment-fact insert-time-only resolution. Facts carry stable StudentNumber; reads match current student by StudentNumber NOT the mutable StudentKey (durable fix for SCD-reversion stranding, LIVE 2026-10-13).
- [Historical Roster Reconciliation](project_historical_roster_reconciliation.md) â€” window-context reads resolve roster by effective-date join, not current RLS. Displayed TEACHER attribution on reports = as-of the cycle too (2026-11-13); the "admin current-only" wrinkle is about ACCESS scope only â€” never cite it for anything displayed.
- [Submission Validation Strategy](project_submission_validation_strategy.md) â€” 3-layer validate-before-write; THROW 51010+ user-fixable, 51001-09 impossible-state.
- [IPP Type Labelling](project_ipp_type_labelling.md) â€” confirm prompts name the TYPE ("Yes (Literacy IPP)" / "Yes (Math IPP)"); helper ippTypeLabel(subject).
- [SQL Reserved-Word Aliases](feedback_sql_reserved_word_aliases.md) â€” never RowCount / Group / Current as aliases in Fabric.
- [SCD Same-Day Re-Version Fix](project_scd_same_day_reversion_fix.md) â€” same-day re-ingest reversed SCD window; fixed in-place update in all 4 merge procs. LIVE 2026-06-24.
- [SCD Staff Deactivation-Marker Restack Fix](project_scd_staff_marker_restack_fix.md) â€” usp_MergeStaff stacked dup IsCurrent markers; guards added; remediate w/ fix_dimstaff_stacked_markers.sql. LIVE 2026-09-08.
- [Section Under-Capture Bug (RESOLVED)](project_section_undercapture_bug.md) â€” RESOLVED 2026-09-09: FactEnrollment.ActiveFlag=0 froze SectionKeys; not a TVF bug.

## Power Apps (largely superseded by web app)
- [Power Apps Write Pattern](project_powerapps_write_pattern.md) â€” writes via wrapper stored procs (Patch/SubmitForm don't work w/ Fabric).
- [Power Apps Build Approach](project_powerapps_build_approach.md) â€” VS Code YAML via pac unpack/pack; Studio for bootstrap + polish.
- [Power Apps Copilot Grounding](project_powerapps_copilot_grounding.md) â€” DEPRECATED 2026-05-13, historical only.
- [Power Apps YAML Templates](project_powerapps_yaml_templates.md) â€” verified control template identifiers + data source naming.
- [Power Apps Control Names Globally Unique](feedback_powerapps_unique_control_names.md) â€” every control name app-unique; rename copied gallery children.
- [Power Apps BIGINT Precision](project_powerapps_bigint_precision.md) â€” cast 19-digit surrogate keys to VARCHAR(20) for Power Fx (16-digit double).
- [Power Apps Loading State Pattern](project_powerapps_loading_state_pattern.md) â€” ClearCollect in OnVisible + loaded flag + dual loading/empty labels.
- [Power Apps ForAll No Set](feedback_powerapps_forall_no_set.md) â€” Set() blocked in ForAll; use Collect() + CountRows().
- [Power Apps Data Source Refresh](feedback_powerapps_data_source_refresh.md) â€” ADD col = reload; RENAME/TYPE/REMOVE = remove+re-add data source.
- [Power Fx Formula Contexts](feedback_powerapps_formula_contexts.md) â€” `=` prefix in .pa.yaml only, not Studio formula bar.
- [Power Apps Studio UI Paths](feedback_powerapps_studio_ui.md) â€” don't dictate UI menu paths; describe outcomes.
- [Power Fx Identifier Column Args](feedback_powerfx_identifier_column_args.md) â€” bare identifiers for column-name args, not quoted strings.
- [Power Apps Responsive Sizing](project_powerapps_responsive_sizing.md) â€” Parent.Height-relative formulas, not fixed pixel heights.
- [WebContents Connector â€” No Binary Uploads](feedback_webcontents_no_binary.md) â€” Entra preauth connector is text-only; use plain HTTP + SP for file writes.

## Stakeholders / product
- [Stakeholder Preferences](project_stakeholder_preferences.md) â€” FSL + English Literacy coordinators diverge; don't auto-extend one's asks to both.
- [Teacher-Testing Sprint (deadlines)](project_teacher_testing_sprint.md) â€” testing week of 2026-09-14; time-boxed.
- [Grace Period Hidden From Teachers](project_grace_period_hidden_from_teachers.md) â€” the post-close grace window stays OUT of all teacher-facing comms, by design, so teachers don't rely on it and procrastinate. Admin/CHANGELOG docs still cover it.
- [Homeroom Chips Unwieldy](project_homeroom_chips_unwieldy.md) â€” homeroom smart-chips don't scale; denser/searchable picker (superseded by group redesign).

## Shipped / in-flight features
- [Writing Trait Exclusion (v1.0.0 LIVE)](project_writing_trait_exclusion.md) â€” data-driven `WritingTraitExclusion` (traitÃ—gradeÃ—programÃ—benchmark-month); excluded trait stored as `-` (â‰ NULL), dropped from avg/reports. Traits now VARCHAR; average via `IN ('1'..'4')` allow-list (Fabric `TRY_CAST('-')=0`). LIVE 2026-10-02.
- [Roster Materialization (0.6.2 LIVE)](project_roster_materialization.md) â€” membership tables (`SectionRosterMembership`/`TeacherRosterMembership`) + card-metadata pass-through; warm roster ~3.47sâ†’~2.3s. Two tables in LOCKSTEP with the roster TVFs; D (fast-path routing) parked. **SECTION-STABLE fix LIVE 2026-10-13**: rebuild matches enrolment by stable `SectionID` (all section versions) + student by `StudentNumber`, not the mutable surrogate â€” closed cycles no longer strand on a section re-version; departed-during-window students kept (paper backfill). TEACHER-axis version still OPEN.
- [Image Versioning Scheme (DONE)](project_image_versioning_scheme.md) â€” RESOLVED 2026-09-08: semver-tagged prod images, tar by version, CHANGELOG + git tag; first = v0.3.0.
- [Prior-Year Baseline (v0.4.0 SHIPPED)](project_prior_year_baseline.md) â€” Reading prior-year starting point LIVE 2026-09-10; COALESCE(prior facts, baseline seed). Writing has NO baseline.
- [Group Display Redesign](project_group_display_redesign.md) â€” shared choose-a-group picker (teacher own classes / oversight lenses + filters). Built via the makeover Phase 1.
- [Programming Makeover (IPP+Adaptations)](project_programming_makeover.md) â€” DONE through Phase 2 on dev/0.5.0: `/programming` nav, window-less picker (tvf_ProgrammingGroups/Roster) + IPPâŸ·Adaptations grid with the data-driven 2-way/4-way FI cell.
- [Assessment Language Tracks + Course Write-Scoping](project_assessment_language_tracks.md) â€” dual-language EN/FR reading+writing via the CYCLE (no fact schema change); course-based WRITE scoping (list pending); J020 reading = English only. Reuses the IPP/Adaptation split rule.
- [Writing Scribed Score Code](project_writing_scribed_score_code.md) â€” "SCR" on Conventions ONLY, omitted from the average; ConventionsScoreâ†’VARCHAR. Dev 2026-09-17; live pending.
- [Maintenance Mode (BUILT dev/0.5.0)](project_maintenance_mode.md) â€” graceful poll-based lockout for emergency container swaps: AppMaintenance row + set/clear procs + /api/status; staged bannerâ†’lockâ†’auto-saveâ†’down overlay; sysadmin one-click Clear + sign-in on overlay. Fabric: no TINYINT; ;THROW needs BEGINâ€¦END.

## Backlog / wishlist (NOT built)
- [Feature Ideas & Backlog](project_feature_ideas_and_backlog.md) â€” triaged queue. OPEN near-term: maintenance/ingest dev dry-run. Forward: areas meeting/exceeding report, IPP auto-pair, writing-cohort re-scope â†’ math reporting, split-grade pacing, linked-task carry-forward â†’ a11y sweep, dark mode. Prune as items ship.
- [Subjectâ†”Course Dim (QoL)](project_subject_course_dim.md) â€” course-codeâ†’subject Dim; filter/scope group-picker sections.
- [Perf/Load QoL Backlog (POST-v1.1)](project_perf_qol_backlog.md) â€” batch the per-student save loop, cache static lookups, parallelise roster awaits, don't poll hidden tabs. Not launch-blocking.
- [Dark Mode (POST-1.0 QoL)](project_dark_mode.md) â€” 2nd palette + hardcoded-color audit + trigger; DB achievement colors the design question. ~Â½ day system-only.
