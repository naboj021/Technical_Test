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

    SELECT
        COUNT(*)                                                    AS UnitsTested,
        COUNT(CASE WHEN ts.Result = 'PASS' THEN 1 END)              AS UnitsPassed,
        CAST(
            CAST(COUNT(CASE WHEN ts.Result = 'PASS' THEN 1 END) AS DECIMAL(18, 4))
            / NULLIF(COUNT(*), 0) * 100
        AS DECIMAL(5, 2))                                           AS FirstPassYieldPct
    FROM dbo.TestSessions AS ts
    WHERE ts.StartedAt BETWEEN @FromDate AND @ToDate;
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
