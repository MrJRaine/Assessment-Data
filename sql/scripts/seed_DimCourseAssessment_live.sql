/*******************************************************************************
 * Script: seed_DimCourseAssessment_live.sql
 * Purpose: LIVE seed of DimCourseAssessment from the real PowerSchool course list
 *          (docs/course-assessment-mapping.md, provided 2026-09-17).
 *            ELA P-12 + Immersion ELA 3-6 -> English literacy
 *            FLA                            -> French literacy
 *            Math                           -> Math
 *          A Language-Arts course = Reading + Writing in its language.
 * Idempotent: clears then re-seeds. Add/remove a course later = INSERT/DELETE a row.
 * VERIFY the codes against a clean PS export before running on live -- the source
 *          table was pasted and had a few dupes/typos (see the docs note).
 * Region: Canada East (PIIDPA compliant)
 ******************************************************************************/

DELETE FROM DimCourseAssessment;

-- ELA P-12 (English-program + immersion 7-12 English LA) -> English literacy
INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES
    ('ENG15PR','English','Literacy',1,'ELA P-12',GETDATE()),('ENG15PRIP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG151','English','Literacy',1,'ELA P-12',GETDATE()),('ENG151IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG152','English','Literacy',1,'ELA P-12',GETDATE()),('ENG152IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG153','English','Literacy',1,'ELA P-12',GETDATE()),('ENG153IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG164','English','Literacy',1,'ELA P-12',GETDATE()),('ENG4IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG165','English','Literacy',1,'ELA P-12',GETDATE()),('ENG5IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG166','English','Literacy',1,'ELA P-12',GETDATE()),('ENG6IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG187','English','Literacy',1,'ELA P-12',GETDATE()),('ENG7IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG188','English','Literacy',1,'ELA P-12',GETDATE()),('ENG8IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG9','English','Literacy',1,'ELA P-12',GETDATE()),('ENG9IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG10','English','Literacy',1,'ELA P-12',GETDATE()),('ENG10IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG10O2','English','Literacy',1,'ELA P-12',GETDATE()),('EN10P','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG10PIP','English','Literacy',1,'ELA P-12',GETDATE()),('ENG11C','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG11','English','Literacy',1,'ELA P-12',GETDATE()),('ENG11O2','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG11IP','English','Literacy',1,'ELA P-12',GETDATE()),('ENG11ADV','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG12','English','Literacy',1,'ELA P-12',GETDATE()),('ENG12IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG12ADV','English','Literacy',1,'ELA P-12',GETDATE()),('ECM11','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ECM11IP','English','Literacy',1,'ELA P-12',GETDATE()),('ECM12','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ECM12IP','English','Literacy',1,'ELA P-12',GETDATE()),('ECM12O2','English','Literacy',1,'ELA P-12',GETDATE()),
    ('EN10PIP','English','Literacy',1,'ELA P-12',GETDATE()),('ENG10PRE','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG12O2','English','Literacy',1,'ELA P-12',GETDATE()),('IBENG11','English','Literacy',1,'ELA P-12',GETDATE()),
    ('IBENG12HL','English','Literacy',1,'ELA P-12',GETDATE()),('IBENG12SL','English','Literacy',1,'ELA P-12',GETDATE()),
    ('LAL10','English','Literacy',1,'ELA P-12',GETDATE()),('ENGAH12','English','Literacy',1,'ELA P-12',GETDATE()),
    ('CANLIT12','English','Literacy',1,'ELA P-12',GETDATE()),('CLT12IP','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG12C','English','Literacy',1,'ELA P-12',GETDATE()),('ECM11O2','English','Literacy',1,'ELA P-12',GETDATE()),
    ('ENG12AP','English','Literacy',1,'ELA P-12',GETDATE());

-- Immersion ELA 3-6 (early-immersion English LA) -> English literacy
INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES
    ('ELAANG3','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),('ELA3IP','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),
    ('ELAANG164','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),('ELA4IP','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),
    ('ELAANG165','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),('ELA5IP','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),
    ('ELAANG166','English','Literacy',1,'Immersion ELA 3-6',GETDATE()),('ELA6IP','English','Literacy',1,'Immersion ELA 3-6',GETDATE());

-- FLA (Francais / French Immersion LA) -> French literacy
INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES
    ('FR151IM','French','Literacy',1,'FLA',GETDATE()),('FR151IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FR15PRIM','French','Literacy',1,'FLA',GETDATE()),('FR151PRIMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FR152IM','French','Literacy',1,'FLA',GETDATE()),('FR152IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FR153IM','French','Literacy',1,'FLA',GETDATE()),('FR153IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FR164IM','French','Literacy',1,'FLA',GETDATE()),('FR165IM','French','Literacy',1,'FLA',GETDATE()),
    ('FRAFLA4IP','French','Literacy',1,'FLA',GETDATE()),('FRAFLA5IP','French','Literacy',1,'FLA',GETDATE()),
    ('FRAFLA6IP','French','Literacy',1,'FLA',GETDATE()),('FR166IM','French','Literacy',1,'FLA',GETDATE()),
    ('FR187EIM','French','Literacy',1,'FLA',GETDATE()),('FR188EIM','French','Literacy',1,'FLA',GETDATE()),
    ('FR9EIM','French','Literacy',1,'FLA',GETDATE()),('FR10IM','French','Literacy',1,'FLA',GETDATE()),
    ('FR11IM','French','Literacy',1,'FLA',GETDATE()),('FR12IM','French','Literacy',1,'FLA',GETDATE()),
    ('FR187LIM','French','Literacy',1,'FLA',GETDATE()),('FR188LIM','French','Literacy',1,'FLA',GETDATE()),
    ('FR6IN','French','Literacy',1,'FLA',GETDATE()),('FRA8IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FRAFR6INIP','French','Literacy',1,'FLA',GETDATE()),('FR9IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FRA10IMIP','French','Literacy',1,'FLA',GETDATE()),('FRA11IMIP','French','Literacy',1,'FLA',GETDATE()),
    ('FRA12IMIP','French','Literacy',1,'FLA',GETDATE()),('FRA10PREBI','French','Literacy',1,'FLA',GETDATE()),
    ('FRA7IMIP','French','Literacy',1,'FLA',GETDATE());

-- Math P-6 (Math single-track) -> Math
INSERT INTO DimCourseAssessment (CourseCode, Language, Kind, ActiveFlag, Notes, LastUpdated) VALUES
    ('MT15PR',NULL,'Math',1,'Math P-6',GETDATE()),('MT15PRIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT151',NULL,'Math',1,'Math P-6',GETDATE()),('MT151IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT152',NULL,'Math',1,'Math P-6',GETDATE()),('MT152IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT153',NULL,'Math',1,'Math P-6',GETDATE()),('MT153IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT164',NULL,'Math',1,'Math P-6',GETDATE()),('MT4IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT165',NULL,'Math',1,'Math P-6',GETDATE()),('MT5IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT166',NULL,'Math',1,'Math P-6',GETDATE()),('MT6IP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT15PRIM',NULL,'Math',1,'Math P-6',GETDATE()),('MT15PRIMIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT151IM',NULL,'Math',1,'Math P-6',GETDATE()),('MT151IMIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT152IM',NULL,'Math',1,'Math P-6',GETDATE()),('MT152IMIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MT153IM',NULL,'Math',1,'Math P-6',GETDATE()),('MT153IMIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MTH164IM',NULL,'Math',1,'Math P-6',GETDATE()),('MTH165IM',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MTH166IM',NULL,'Math',1,'Math P-6',GETDATE()),('MAT4IMIP',NULL,'Math',1,'Math P-6',GETDATE()),
    ('MAT5IMIP',NULL,'Math',1,'Math P-6',GETDATE()),('MAT6IMIP',NULL,'Math',1,'Math P-6',GETDATE());

SELECT Language, Kind, COUNT(*) AS Courses FROM DimCourseAssessment GROUP BY Language, Kind ORDER BY Kind, Language;
