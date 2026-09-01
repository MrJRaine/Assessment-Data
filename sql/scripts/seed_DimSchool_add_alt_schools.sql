/*******************************************************************************
 * Seed patch: add the two alternative high schools to DimSchool
 * Purpose: 1254 Yarmouth Alternative High School and 1255 Digby Alternative
 *          High School were missing from the DimSchool seed. Add them so
 *          students/staff at those schools resolve to a school name.
 * Created: 2026-08-27
 * Region: Canada East (PIIDPA compliant)
 *
 * Idempotent — safe to re-run. DimSchool is preserved by the production reset,
 * so this only needs running once on each warehouse.
 *
 * NOTE: Abbreviation values below (YAHS / DAHS) are a best guess — correct them
 * to the school's real short form if it differs (Abbreviation is nullable; the
 * app falls back to SchoolID when it's blank). Community is from the school name.
 ******************************************************************************/

IF NOT EXISTS (SELECT 1 FROM DimSchool WHERE SchoolID = '1254')
    INSERT INTO DimSchool (SchoolID, SchoolName, Abbreviation, Community, ActiveFlag, LastUpdated)
    VALUES ('1254', 'Yarmouth Alternative High School', 'YAHS', 'Yarmouth', 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM DimSchool WHERE SchoolID = '1255')
    INSERT INTO DimSchool (SchoolID, SchoolName, Abbreviation, Community, ActiveFlag, LastUpdated)
    VALUES ('1255', 'Digby Alternative High School', 'DAHS', 'Digby', 1, GETDATE());
GO

SELECT SchoolID, SchoolName, Abbreviation, Community
FROM DimSchool WHERE SchoolID IN ('1254', '1255');
