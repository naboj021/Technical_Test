USE TestOps;
GO

/* ------------------------------------------------------------------
   First Pass Yield

   Definition agreed with production:
       First Pass Yield = boards that passed on their FIRST test attempt
                          / boards tested
                          x 100

   Boards that fail, get repaired and pass on a later attempt do NOT
   count towards first pass yield. They are covered by the separate
   final yield figure.

   Written 2024. Maintained since by several people.
   ------------------------------------------------------------------ */

IF OBJECT_ID('dbo.usp_GetFirstPassYield', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetFirstPassYield;
GO

CREATE PROCEDURE dbo.usp_GetFirstPassYield
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    /* One row per board: only its first test attempt defines FPY. */
    SELECT
        COUNT(*)                                                    AS UnitsTested,
        COUNT(CASE WHEN ts.Result = 'PASS' THEN 1 END)              AS UnitsPassed,
        CAST(
            CAST(COUNT(CASE WHEN ts.Result = 'PASS' THEN 1 END) AS DECIMAL(18, 4))
            / NULLIF(COUNT(*), 0) * 100
        AS DECIMAL(5, 2))                                           AS FirstPassYieldPct
    FROM dbo.TestSessions AS ts
    WHERE ts.AttemptNo = 1
      AND ts.StartedAt >= @FromDate
      AND ts.StartedAt < DATEADD(DAY, 1, @ToDate);
END
GO

/* ------------------------------------------------------------------
   Final Yield

   Uses the same cohort as FPY (boards first tested in the period),
   and counts a board as passed if any of its attempts up to the end
   of that reporting period passed.
   ------------------------------------------------------------------ */

IF OBJECT_ID('dbo.usp_GetFinalYield', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetFinalYield;
GO

CREATE PROCEDURE dbo.usp_GetFinalYield
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Cohort AS (
        SELECT ts.SerialNumber
        FROM dbo.TestSessions AS ts
        WHERE ts.AttemptNo = 1
          AND ts.StartedAt >= @FromDate
          AND ts.StartedAt < DATEADD(DAY, 1, @ToDate)
    ), PassedBoards AS (
        SELECT DISTINCT ts.SerialNumber
        FROM dbo.TestSessions AS ts
        WHERE ts.Result = 'PASS'
          AND ts.StartedAt < DATEADD(DAY, 1, @ToDate)
    )
    SELECT
        COUNT(*)                                      AS UnitsTested,
        COUNT(p.SerialNumber)                         AS UnitsPassed,
        CAST(
            CAST(COUNT(p.SerialNumber) AS DECIMAL(18, 4))
            / NULLIF(COUNT(*), 0) * 100
        AS DECIMAL(5, 2))                             AS FinalYieldPct
    FROM Cohort AS c
    LEFT JOIN PassedBoards AS p
      ON p.SerialNumber = c.SerialNumber;
END
GO

/* Daily breakdown used by the dashboard. */
IF OBJECT_ID('dbo.usp_GetDailyVolume', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetDailyVolume;
GO

CREATE PROCEDURE dbo.usp_GetDailyVolume
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CAST(ts.StartedAt AS DATE)                       AS TestDate,
        COUNT(*)                                         AS UnitsTested,
        COUNT(CASE WHEN ts.Result = 'FAIL' THEN 1 END)   AS UnitsFailed
    FROM dbo.TestSessions AS ts
    WHERE ts.StartedAt >= @FromDate
      AND ts.StartedAt < DATEADD(DAY, 1, @ToDate)
    GROUP BY CAST(ts.StartedAt AS DATE)
    ORDER BY TestDate;
END
GO
