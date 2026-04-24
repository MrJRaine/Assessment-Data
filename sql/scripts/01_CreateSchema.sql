/*******************************************************************************
 * Script: 01_CreateSchema.sql
 * Purpose: Create all dimension and fact tables in dependency order
 * Run this script once against a new Fabric Warehouse to initialize the schema.
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

-- ============================================================
-- DIMENSIONS (no inter-dimension FK dependencies first)
-- ============================================================

:r ../dimensions/DimSchool.sql
:r ../dimensions/DimStudent.sql
:r ../dimensions/DimStaff.sql
:r ../dimensions/DimAssessmentWindow.sql
:r ../dimensions/DimReadingScale.sql
:r ../dimensions/DimCalendar.sql

-- DimSection last — has FK to DimStaff
:r ../dimensions/DimSection.sql

-- ============================================================
-- FACTS
-- ============================================================

:r ../facts/FactEnrollment.sql
:r ../facts/FactAssessmentReading.sql
:r ../facts/FactAssessmentWriting.sql
:r ../facts/FactSubmissionAudit.sql

-- ============================================================
-- RLS SECURITY TABLES (step 5)
-- ============================================================

-- :r ../security/RLS_UserSchoolAccess.sql
-- :r ../security/RLS_UserSectionAccess.sql
