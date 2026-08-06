/* ------------------------------------------------------------------
   TestOps — production test results schema
   ------------------------------------------------------------------ */

IF DB_ID('TestOps') IS NULL
    CREATE DATABASE TestOps;
GO

USE TestOps;
GO

IF OBJECT_ID('dbo.TestSessions', 'U') IS NOT NULL DROP TABLE dbo.TestSessions;
IF OBJECT_ID('dbo.Stations',     'U') IS NOT NULL DROP TABLE dbo.Stations;
IF OBJECT_ID('dbo.Products',     'U') IS NOT NULL DROP TABLE dbo.Products;
GO

CREATE TABLE dbo.Products (
    ProductCode  NVARCHAR(20)  NOT NULL PRIMARY KEY,
    Description  NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.Stations (
    StationCode  NVARCHAR(20) NOT NULL PRIMARY KEY,
    StationType  NVARCHAR(10) NOT NULL
);
GO

/* One row per test attempt on one board at one station.
   AttemptNo = 1 is the first time that serial was tested;
   subsequent attempts follow repair or rework.            */
CREATE TABLE dbo.TestSessions (
    SessionId     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    SerialNumber  NVARCHAR(50)  NOT NULL,
    ProductCode   NVARCHAR(20)  NOT NULL,
    StationCode   NVARCHAR(20)  NULL,
    StartedAt     DATETIME2(0)  NOT NULL,
    Result        NVARCHAR(10)  NOT NULL,
    AttemptNo     INT           NOT NULL CONSTRAINT DF_TestSessions_AttemptNo DEFAULT (1)
);
GO

CREATE INDEX IX_TestSessions_StartedAt ON dbo.TestSessions (StartedAt) INCLUDE (Result, AttemptNo);
CREATE INDEX IX_TestSessions_Serial    ON dbo.TestSessions (SerialNumber, StartedAt);
GO

INSERT INTO dbo.Products (ProductCode, Description) VALUES
    ('PCA-1180', 'Main controller board'),
    ('PCA-2240', 'Power stage'),
    ('PCA-3310', 'Sensor interface'),
    ('PCA-4020', 'Backplane');
GO

INSERT INTO dbo.Stations (StationCode, StationType) VALUES
    ('ICT-01', 'ICT'),
    ('FCT-01', 'FCT'),
    ('AOI-02', 'AOI');
GO
