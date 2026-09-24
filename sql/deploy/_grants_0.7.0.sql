/*───────────────────────────────────────────────────────────────────────────────────────────
  _grants_0.7.0.sql — re-grant the 0.7.0 objects to the app service principal.
  Idempotent: re-running GRANT is a no-op. Required because usp_UpsertReadingAssessment is
  DROP/CREATE with no inline grant (it would otherwise lose EXECUTE and break reading saves).
  The other procs + all TVFs also self-grant; this stage guarantees the whole set regardless.
───────────────────────────────────────────────────────────────────────────────────────────*/

-- Procedures (EXECUTE)
GRANT EXECUTE ON [dbo].[usp_UpsertReadingAssessment] TO [StudentDataAssessment];
GO
GRANT EXECUTE ON [dbo].[usp_UpsertWritingAssessment] TO [StudentDataAssessment];
GO
GRANT EXECUTE ON [dbo].[usp_UpsertMathAssessment] TO [StudentDataAssessment];
GO
GRANT EXECUTE ON [dbo].[usp_UpsertShortCycleHeader] TO [StudentDataAssessment];
GO
GRANT EXECUTE ON [dbo].[usp_SetStaffAppAccess] TO [StudentDataAssessment];
GO

-- Table-valued functions (SELECT)
GRANT SELECT ON [dbo].[tvf_UserAssessmentWindows]     TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_TeacherGroups]             TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_StudentCohort]             TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_StudentAssessmentHistory]  TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_MathCohortGroups]          TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_StudentCohortMath]         TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_StudentCohortRWM]          TO [StudentDataAssessment];
GO
GRANT SELECT ON [dbo].[tvf_StudentRWMHistory]         TO [StudentDataAssessment];
GO
