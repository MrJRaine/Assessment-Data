/*******************************************************************************
 * Table: DimRole
 * Purpose: Reference dimension for PowerSchool staff role codes (the "Group"
 *          field in the Staff export). Maps each PS RoleNumber (1-50) to a
 *          warehouse RoleCode used by FactStaffAssignment for RLS and reporting.
 * SCD Type: N/A (static reference data, seeded once. Update if PS adds/changes
 *           role codes.)
 * Created: 2026-04-29
 * Modified: 2026-04-29 - Expanded RoleCode taxonomy from 4 values to 6:
 *                       added SpecialistTeacher, ProvincialAnalyst, SupportStaff
 *                       per PS admin clarification on role responsibilities.
 *           2026-05-01 - Reclassified RoleNumbers 22 (IB/O2/Co-op Coordinators)
 *                       and 32 (APSEA Itinerant Teachers) from SpecialistTeacher
 *                       to Teacher. Rationale: both roles ARE teachers (vs the
 *                       remaining SpecialistTeacher list which is admin-tier:
 *                       counsellors, registrars, resource teachers). APSEA
 *                       itinerants are external contractors without TCRCE Entra
 *                       accounts and never authenticate to the platform, so
 *                       AccessLevel is moot for them. Side benefit: removes the
 *                       only AccessLevel-branching case in the SchoolAdmins
 *                       DAX RLS — Administrator and remaining SpecialistTeacher
 *                       now have identical staff-visibility rules.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- Warehouse RoleCode taxonomy and RLS implications:
--   'Teacher'           — anyone whose role IS to teach: classroom teachers,
--                         librarians, IB/O2/Co-op coordinators (who teach those
--                         courses), APSEA itinerants. RLS via section-level
--                         FactSectionTeachers (NOT StaffSchoolAccess).
--   'SpecialistTeacher' — school-based non-teaching specialists: counsellors,
--                         registrars, resource teachers. Despite the name (kept
--                         for historical continuity), this RoleCode no longer
--                         includes anyone who actually teaches. Get school-level
--                         RLS via StaffSchoolAccess.
--   'Administrator'     — Principals, VPs, admin assistants. School-level RLS
--                         via StaffSchoolAccess.
--   'RegionalAnalyst'   — TCRCE board-level: superintendent, board directors,
--                         board admin, board services. Multi-school RLS via
--                         StaffSchoolAccess (board scope).
--   'ProvincialAnalyst' — Provincial-level: Dept of Education, evaluation
--                         services. NOT included in the PowerApp security
--                         group at all — these accounts never authenticate to
--                         the app, so they're excluded from StaffSchoolAccess
--                         entirely. Rows are still recorded in DimStaff /
--                         FactStaffAssignment for audit/reporting.
--   'SupportStaff'      — No access to student data in the app. Excluded
--                         entirely from StaffSchoolAccess. Mix of school-
--                         and regional-based positions; the distinction is
--                         irrelevant for RLS since access is denied uniformly.
--   NULL                — Unused or placeholder slot in PS (should not appear
--                         in production exports). ActiveFlag = 0.
--
-- Notes:
--   - RoleNumber 22 (IB, O2, and Co-op Coordinators) → Teacher
--     (they teach the courses they coordinate; reclassified 2026-05-01).
--   - RoleNumber 32 (APSEA Itinerant Teachers)      → Teacher
--     (external contractors who teach across multiple schools; reclassified
--     2026-05-01. Note: APSEA staff don't have TCRCE Entra accounts and
--     never authenticate to the platform, so AccessLevel is functionally
--     irrelevant for them — but Teacher is the correct classification.)
--   - RoleNumber 40 (Coordinators or Consultants)    → RegionalAnalyst
--     (board-level coordinators/consultants — distinct from the school-based
--     coordinators in 22 who are now Teachers).
--   - RoleNumber 50 is a legacy code with a few non-teaching accounts still
--     active per PS admin; mapped to SupportStaff with ActiveFlag=1.

CREATE TABLE DimRole (
    RoleNumber  INT             NOT NULL,   -- Natural key: PS Group number (1-50)
    RoleName    VARCHAR(200)    NOT NULL,   -- PS-side label
    RoleCode    VARCHAR(50)     NULL,       -- Warehouse value used in FactStaffAssignment.RoleCode
    ActiveFlag  BIT             NOT NULL,   -- 1 = real PS role; 0 = unused/placeholder slot
    LastUpdated DATETIME2(0)    NOT NULL
);

INSERT INTO DimRole (RoleNumber, RoleName, RoleCode, ActiveFlag, LastUpdated)
VALUES
    (1,  'Unused 1',                                              NULL,                0, GETDATE()),
    (2,  'Unused 2',                                              NULL,                0, GETDATE()),
    (3,  'Unused 3',                                              NULL,                0, GETDATE()),
    (4,  'Unused 4',                                              NULL,                0, GETDATE()),
    (5,  'Unused 5',                                              NULL,                0, GETDATE()),
    (6,  'Unused 6',                                              NULL,                0, GETDATE()),
    (7,  'Unused 7',                                              NULL,                0, GETDATE()),
    (8,  'Unused 8',                                              NULL,                0, GETDATE()),
    (9,  'DoE PS Admin',                                          'ProvincialAnalyst', 1, GETDATE()),
    (10, 'Board PS Admin',                                        'RegionalAnalyst',   1, GETDATE()),
    (11, 'Admin Assistants Only (PS admin and scheduling)',       'Administrator',     1, GETDATE()),
    (12, 'Registrar/Counsellor',                                  'SpecialistTeacher', 1, GETDATE()),
    (13, 'Admin Assistant - Level 2 (Non-Scheduling)',            'Administrator',     1, GETDATE()),
    (14, 'Adult High School PS Admin',                            'Administrator',     1, GETDATE()),
    (15, 'INTL Admin',                                            'Administrator',     1, GETDATE()),
    (16, 'CSAP Translator',                                       'SupportStaff',      1, GETDATE()),
    (17, 'Admin Assistant - Level 3 (Limited Access)',            'Administrator',     1, GETDATE()),
    (18, 'NA - 18',                                               NULL,                0, GETDATE()),
    (19, 'Registrar (without Counsellor Admin notes)',            'SpecialistTeacher', 1, GETDATE()),
    (20, 'Admin Assistant - Level 2 (Reports and Alert)',         'Administrator',     1, GETDATE()),
    (21, 'Counselor - Level 1 (Walk-In Scheduling)',              'SpecialistTeacher', 1, GETDATE()),
    (22, 'IB, O2, and Co-op Coordinators',                        'Teacher',           1, GETDATE()),
    (23, 'Counselor - Level 2 (Non-Scheduling)',                  'SpecialistTeacher', 1, GETDATE()),
    (24, 'Parent Navigator',                                      'SupportStaff',      1, GETDATE()),
    (25, 'SchoolsPlus Community Outreach',                        'SupportStaff',      1, GETDATE()),
    (26, 'NA - 26',                                               NULL,                0, GETDATE()),
    (27, 'Help Desk',                                             'SupportStaff',      1, GETDATE()),
    (28, 'SchoolsPlus Facilitator',                               'SupportStaff',      1, GETDATE()),
    (29, 'Report Creator',                                        'RegionalAnalyst',   1, GETDATE()),
    (30, 'Evaluation Services - 30',                              'ProvincialAnalyst', 1, GETDATE()),
    (31, 'Mental Health Clinician / CYCPS',                       'SupportStaff',      1, GETDATE()),
    (32, 'APSEA Itinerant Teachers',                              'Teacher',           1, GETDATE()),
    (33, 'Principal/VP Only (scheduling)',                        'Administrator',     1, GETDATE()),
    (34, 'Principal/VP Only (PS admin and scheduling)',           'Administrator',     1, GETDATE()),
    (35, 'Principal/VP Only (no scheduling)',                     'Administrator',     1, GETDATE()),
    (36, 'TIENET Connect',                                        'SupportStaff',      1, GETDATE()),
    (37, 'Counselor - Level 3',                                   'SpecialistTeacher', 1, GETDATE()),
    (38, 'Student Support Worker',                                'SupportStaff',      1, GETDATE()),
    (39, 'Board Admin Assistant',                                 'SupportStaff',      1, GETDATE()),
    (40, 'Coordinators or Consultants',                           'RegionalAnalyst',   1, GETDATE()),
    (41, 'REDs/Superintendent, Board Directors, FOSS, etc.',      'RegionalAnalyst',   1, GETDATE()),
    (42, 'Board-Student Services',                                'RegionalAnalyst',   1, GETDATE()),
    (43, 'Board - Program Services',                              'RegionalAnalyst',   1, GETDATE()),
    (44, 'Board - Service Coordinators (Transportation, etc)',    'SupportStaff',      1, GETDATE()),
    (45, 'Resource Teacher',                                      'SpecialistTeacher', 1, GETDATE()),
    (46, 'Teacher or Librarian (Fee Access)',                     'Teacher',           1, GETDATE()),
    (47, 'Teacher or Librarian',                                  'Teacher',           1, GETDATE()),
    (48, 'Teacher (additional responsibilities)',                 'Teacher',           1, GETDATE()),
    (49, 'Support Staff',                                         'SupportStaff',      1, GETDATE()),
    (50, 'NA - 50',                                               'SupportStaff',      1, GETDATE());
