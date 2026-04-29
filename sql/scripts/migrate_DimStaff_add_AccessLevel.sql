/*******************************************************************************
 * Migration: Add AccessLevel column to DimStaff
 * Created:   2026-04-29
 * Reason:    Replace per-query MAX(CASE) computation in vw_StaffSchoolAccess
 *            with a denormalized snapshot computed once at ingest. AccessLevel
 *            is the staff member's highest-priority school-tier RoleCode from
 *            FactStaffAssignment (priority: RegionalAnalyst > Administrator >
 *            SpecialistTeacher). NULL for staff with no school-tier role
 *            (Teacher-only, ProvincialAnalyst, SupportStaff).
 *
 *            Type 1 (overwrite). Historical AccessLevel is recoverable from
 *            FactStaffAssignment's own Type 2 history if needed.
 *
 *            After this column exists, vw_StaffSchoolAccess should be rebuilt
 *            (see migrate_vw_StaffSchoolAccess_simplify.sql) — it no longer
 *            joins FactStaffAssignment or aggregates RoleCodes; it just
 *            unpacks HomeSchoolID + CanChangeSchool from DimStaff.
 *
 *            Note (Fabric quirk): ALTER TABLE ADD COLUMN cannot run in the same
 *            batch as anything that references the new column — Fabric parses
 *            the whole script before executing. So this migration ONLY does the
 *            ALTER. Population is the responsibility of the staff merge proc
 *            (Step 8) when it next runs.
 * Region:    Canada East (PIIDPA compliant)
 ******************************************************************************/

ALTER TABLE DimStaff
ADD AccessLevel VARCHAR(50) NULL;
