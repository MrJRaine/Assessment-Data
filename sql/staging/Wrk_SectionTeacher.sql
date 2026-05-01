/*******************************************************************************
 * Table: Wrk_SectionTeacher
 * Purpose: Typed working set for the FactSectionTeachers merge. Populated by
 *          usp_MergeSectionTeachers from the UNION of:
 *            (a) Stg_Section primary teacher rows  -> TeacherRole = 'Primary'
 *            (b) Stg_CoTeacher rows                -> TeacherRole normalized
 *
 *          Translations applied:
 *            - TeacherEmail lowercased (matches DimStaff business key
 *              convention; matches USERPRINCIPALNAME() at RLS time)
 *            - TeacherRole normalized:
 *                'Co-teacher' (any case) -> 'CoTeacher'
 *                'Support' / 'Substitute' / 'Primary' -> kept (case-corrected)
 *            - Empty Email rows EXCLUDED at Wrk-build (cannot key the bridge
 *              without an email; counted as a warning by the merge proc)
 *            - DISTINCT on (SectionID, TeacherEmail, TeacherRole) — defensive
 *              dedup in case the same triple appears in both Stg_Section and
 *              Stg_CoTeacher (shouldn't happen in production, but cheap to
 *              guard against)
 *
 *          The (SectionID, TeacherEmail, TeacherRole) triple is the natural
 *          key. SourceSystemID is captured for primary-teacher rows (= PS
 *          section ID) and NULL for co-teachers (PS Co-Teacher report has
 *          no per-assignment ID).
 * SCD Type: N/A (truncate-and-reload on every ingest)
 * Created: 2026-05-01
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

CREATE TABLE Wrk_SectionTeacher (
    SectionID           VARCHAR(50)     NOT NULL,
    TeacherEmail        VARCHAR(255)    NOT NULL,
    TeacherRole         VARCHAR(50)     NOT NULL,
    SourceSystemID      VARCHAR(50)     NULL        -- PS section ID for primary rows; NULL for co-teacher rows
);
