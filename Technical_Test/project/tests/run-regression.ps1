param(
    [string]$DotNet = "dotnet"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$sqlcmd = "/opt/mssql-tools18/bin/sqlcmd"
$container = "testops-sql"
$password = "Str0ng!Passw0rd"
$failures = [System.Collections.Generic.List[string]]::new()

# Fail before resetting the database if the requested SDK executable cannot be
# resolved. Otherwise PowerShell treats a missing native command as a
# non-terminating error and the final summary can be misleading.
$dotNetCommand = Get-Command $DotNet -ErrorAction SilentlyContinue
if ($null -eq $dotNetCommand) {
    Write-Error "The .NET SDK executable '$DotNet' was not found. Install .NET 8, add dotnet to PATH, or pass -DotNet with the full path to dotnet.exe."
    exit 1
}
$DotNet = $dotNetCommand.Source

function Invoke-Sql([string]$query) {
    $output = docker exec $container $sqlcmd -S localhost -U sa -P $password -C `
        -d TestOps -h -1 -W -s "," -Q "SET NOCOUNT ON; $query" 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    return ($output | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
}

function Check([bool]$condition, [string]$name, [string]$details) {
    if ($condition) {
        Write-Host "PASS  $name"
    } else {
        Write-Host "FAIL  $name - $details" -ForegroundColor Red
        $failures.Add("$name - $details")
    }
}

Push-Location $projectRoot
try {
    # Every run starts from the supplied January fixture.
    powershell -ExecutionPolicy Bypass -File .\db\setup.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Database setup failed." }

    $firstPass = Invoke-Sql "EXEC dbo.usp_GetFirstPassYield @FromDate='2026-01-01', @ToDate='2026-01-31';"
    Check ($firstPass -eq "2139,1879,87.84") `
        "January first-pass yield" `
        "expected 2139,1879,87.84; actual $firstPass"

    $repairScenario = Invoke-Sql @"
BEGIN TRANSACTION;
INSERT dbo.TestSessions (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo) VALUES
('TEST-REPAIR', 'PCA-1180', 'ICT-01', '2030-01-10 09:00:00', 'FAIL', 1),
('TEST-REPAIR', 'PCA-1180', 'ICT-01', '2030-01-10 10:00:00', 'PASS', 2),
('TEST-FIRST-PASS', 'PCA-1180', 'ICT-01', '2030-01-10 11:00:00', 'PASS', 1);
EXEC dbo.usp_GetFirstPassYield @FromDate='2030-01-01', @ToDate='2030-01-31';
ROLLBACK TRANSACTION;
"@
    Check ($repairScenario -eq "2,1,50.00") `
        "Repaired pass does not count as first-pass success" `
        "expected 2,1,50.00; actual $repairScenario"

    $endDateScenario = Invoke-Sql @"
BEGIN TRANSACTION;
INSERT dbo.TestSessions (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo) VALUES
('TEST-DATE-START', 'PCA-1180', 'ICT-01', '2031-01-01 09:00:00', 'PASS', 1),
('TEST-DATE-END', 'PCA-1180', 'ICT-01', '2031-01-31 15:00:00', 'PASS', 1);
EXEC dbo.usp_GetFirstPassYield @FromDate='2031-01-01', @ToDate='2031-01-31';
ROLLBACK TRANSACTION;
"@
    Check ($endDateScenario -eq "2,2,100.00") `
        "End date includes the full day" `
        "expected 2,2,100.00; actual $endDateScenario"

    $finalOutput = docker exec $container $sqlcmd -S localhost -U sa -P $password -C `
        -d TestOps -h -1 -W -s "," -Q "SET NOCOUNT ON; EXEC dbo.usp_GetFinalYield @FromDate='2026-01-01', @ToDate='2026-01-31';" 2>&1
    $finalExit = $LASTEXITCODE
    $finalRow = ($finalOutput | Where-Object { $_.Trim() } | Select-Object -Last 1).Trim()
    Check (($finalExit -eq 0) -and ($finalRow -eq "2139,2043,95.51")) `
        "January final yield" `
        "expected 2139,2043,95.51; procedure missing or actual output differs"

    $finalCutoffScenario = Invoke-Sql @"
BEGIN TRANSACTION;
INSERT dbo.TestSessions (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo) VALUES
('TEST-LATE-PASS', 'PCA-1180', 'ICT-01', '2032-01-10 09:00:00', 'FAIL', 1),
('TEST-LATE-PASS', 'PCA-1180', 'ICT-01', '2032-02-01 09:00:00', 'PASS', 2),
('TEST-IN-PERIOD-REPAIR', 'PCA-1180', 'ICT-01', '2032-01-10 10:00:00', 'FAIL', 1),
('TEST-IN-PERIOD-REPAIR', 'PCA-1180', 'ICT-01', '2032-01-31 23:59:59', 'PASS', 2),
('TEST-DIRECT-PASS', 'PCA-1180', 'ICT-01', '2032-01-10 11:00:00', 'PASS', 1);
EXEC dbo.usp_GetFinalYield @FromDate='2032-01-01', @ToDate='2032-01-31';
ROLLBACK TRANSACTION;
"@
    Check ($finalCutoffScenario -eq "3,2,66.67") `
        "Final yield is measured as of period end" `
        "expected 3,2,66.67 with the February PASS excluded; actual $finalCutoffScenario"

    $emptyCohort = Invoke-Sql `
        "EXEC dbo.usp_GetFinalYield @FromDate='2040-01-01', @ToDate='2040-01-31';"
    Check ($emptyCohort -eq "0,0,NULL") `
        "Final yield handles an empty cohort" `
        "expected 0,0,NULL without a divide-by-zero error; actual $emptyCohort"

    $page = Invoke-WebRequest -Uri "http://localhost:8080/?from=2026-01-01&to=2026-01-31" -UseBasicParsing
    Check (($page.StatusCode -eq 200) `
        -and ($page.Content -match "First pass yield") `
        -and ($page.Content -match "87\.84%") `
        -and ($page.Content -match "Final yield") `
        -and ($page.Content -match "95\.51%")) `
        "Dashboard shows first-pass and final yield" `
        "expected HTTP 200 with 87.84% FPY and 95.51% final yield"

    $before = [int](Invoke-Sql "SELECT COUNT(*) FROM dbo.TestSessions;")
    $savedErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $firstImport = & $DotNet run --project .\importer -- .\data\test_export_2026-02.csv 2>&1
    $firstExit = $LASTEXITCODE
    $afterFirst = [int](Invoke-Sql "SELECT COUNT(*) FROM dbo.TestSessions;")
    $secondImport = & $DotNet run --project .\importer -- .\data\test_export_2026-02.csv 2>&1
    $secondExit = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorPreference
    $afterSecond = [int](Invoke-Sql "SELECT COUNT(*) FROM dbo.TestSessions;")

    Check (($firstExit -eq 0) -and ($afterFirst -eq ($before + 1165))) `
        "Real export imports 1165 unique attempts" `
        "before=$before after-first=$afterFirst exit=$firstExit"
    Check (($secondExit -eq 0) -and ($afterSecond -eq $afterFirst)) `
        "Importer re-run is idempotent" `
        "after-first=$afterFirst after-second=$afterSecond exit=$secondExit"

    $duplicateKeys = [int](Invoke-Sql @"
SELECT COUNT(*) FROM (
    SELECT SerialNumber, AttemptNo
    FROM dbo.TestSessions
    WHERE StartedAt >= '2026-02-01' AND StartedAt < '2026-03-01'
    GROUP BY SerialNumber, AttemptNo
    HAVING COUNT(*) > 1
) AS duplicates;
"@)
    Check ($duplicateKeys -eq 0) `
        "No duplicate board-attempt keys" `
        "found $duplicateKeys duplicated keys"

    $conflictingFailures = [int](Invoke-Sql @"
SELECT COUNT(*)
FROM dbo.TestSessions
WHERE AttemptNo = 1
  AND Result = 'FAIL'
  AND SerialNumber IN (
      'SN-090739', 'SN-090646', 'SN-090921',
      'SN-090214', 'SN-090092', 'SN-090014'
  );
"@)
    Check ($conflictingFailures -eq 6) `
        "Ambiguous attempts use the documented FAIL-wins rule" `
        "expected 6 conservative FAIL results; actual $conflictingFailures"

    $conflictWarnings = [regex]::Matches(($firstImport -join "`n"), "(?m)^WARNING line ").Count
    Check ($conflictWarnings -eq 7) `
        "Every source conflict is visible" `
        "expected 7 conflict warnings for 6 keys; actual $conflictWarnings"

    # A scheduler can overlap runs. Exercise the database constraint and
    # serializable transaction with two importer processes starting together.
    powershell -ExecutionPolicy Bypass -File .\db\setup.ps1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Database reset for concurrent test failed." }

    $importerDll = Join-Path $projectRoot "importer\bin\Debug\net8.0\Importer.dll"
    $exportPath = Join-Path $projectRoot "data\test_export_2026-02.csv"
    $concurrentFiles = 1..4 | ForEach-Object {
        Join-Path ([System.IO.Path]::GetTempPath()) "testops-concurrent-$PID-$_.log"
    }
    try {
        $process1 = Start-Process -FilePath $DotNet -ArgumentList @($importerDll, $exportPath) `
            -RedirectStandardOutput $concurrentFiles[0] -RedirectStandardError $concurrentFiles[1] -PassThru
        $process2 = Start-Process -FilePath $DotNet -ArgumentList @($importerDll, $exportPath) `
            -RedirectStandardOutput $concurrentFiles[2] -RedirectStandardError $concurrentFiles[3] -PassThru
        $process1.WaitForExit()
        $process2.WaitForExit()
        $process1.Refresh()
        $process2.Refresh()
        $afterConcurrent = [int](Invoke-Sql "SELECT COUNT(*) FROM dbo.TestSessions;")
        $summary1 = Get-Content -Raw -LiteralPath $concurrentFiles[0]
        $summary2 = Get-Content -Raw -LiteralPath $concurrentFiles[2]

        Check ($process1.HasExited -and $process2.HasExited `
            -and ($summary1 -match "Import complete\.") `
            -and ($summary2 -match "Import complete\.") `
            -and ($afterConcurrent -eq 3474)) `
            "Overlapping scheduled runs remain idempotent" `
            "completed1=$($process1.HasExited) completed2=$($process2.HasExited) rows=$afterConcurrent"
    } finally {
        $concurrentFiles | ForEach-Object {
            Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
        }
    }

    $databaseConflictCsv = Join-Path ([System.IO.Path]::GetTempPath()) "testops-db-conflict-$PID.csv"
    try {
        Invoke-Sql @"
INSERT dbo.TestSessions (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo)
VALUES ('SN-DB-CONFLICT', 'PCA-1180', 'ICT-01', '2026-03-01 10:00:00', 'PASS', 1);
SELECT 'OK';
"@ | Out-Null
        @(
            "serial_number,product_code,station_code,started_at,result,attempt_no",
            "SN-DB-CONFLICT,PCA-1180,ICT-01,2026-03-01 10:00:00,FAIL,1"
        ) | Set-Content -LiteralPath $databaseConflictCsv -Encoding UTF8

        $ErrorActionPreference = "Continue"
        $databaseConflictOutput = & $DotNet run --project .\importer -- $databaseConflictCsv 2>&1
        $databaseConflictExit = $LASTEXITCODE
        $ErrorActionPreference = $savedErrorPreference
        $databaseConflictText = $databaseConflictOutput -join "`n"
        $databaseResult = Invoke-Sql `
            "SELECT Result FROM dbo.TestSessions WHERE SerialNumber='SN-DB-CONFLICT' AND AttemptNo=1;"

        Check (($databaseConflictExit -eq 0) `
            -and ($databaseResult -eq "FAIL") `
            -and ($databaseConflictText -match "existing=PASS, incoming=FAIL, resolved=FAIL") `
            -and ($databaseConflictText -match "1 updated due to conflicts")) `
            "Existing PASS is updated by an incoming FAIL and reported" `
            "exit=$databaseConflictExit result=$databaseResult output='$databaseConflictText'"

        @(
            "serial_number,product_code,station_code,started_at,result,attempt_no",
            "SN-DB-CONFLICT,PCA-1180,ICT-01,2026-03-01 10:00:00,PASS,1"
        ) | Set-Content -LiteralPath $databaseConflictCsv -Encoding UTF8

        $ErrorActionPreference = "Continue"
        $retainedConflictOutput = & $DotNet run --project .\importer -- $databaseConflictCsv 2>&1
        $retainedConflictExit = $LASTEXITCODE
        $ErrorActionPreference = $savedErrorPreference
        $retainedConflictText = $retainedConflictOutput -join "`n"
        $retainedResult = Invoke-Sql `
            "SELECT Result FROM dbo.TestSessions WHERE SerialNumber='SN-DB-CONFLICT' AND AttemptNo=1;"

        Check (($retainedConflictExit -eq 0) `
            -and ($retainedResult -eq "FAIL") `
            -and ($retainedConflictText -match "existing=FAIL, incoming=PASS, resolved=FAIL") `
            -and ($retainedConflictText -match "0 updated due to conflicts")) `
            "Existing FAIL is retained against an incoming PASS and reported" `
            "exit=$retainedConflictExit result=$retainedResult output='$retainedConflictText'"
    } finally {
        Remove-Item -LiteralPath $databaseConflictCsv -Force -ErrorAction SilentlyContinue
    }

    $invalidCsv = Join-Path ([System.IO.Path]::GetTempPath()) "testops-invalid-$PID.csv"
    try {
        @(
            "serial_number,product_code,station_code,started_at,result,attempt_no",
            "SN-TEST-VALID,PCA-1180,ICT-01,2026-02-21 10:00:00,PASS,1",
            "SN-TEST-BAD,PCA-1180,ICT-01,not-a-date,PASS,1"
        ) | Set-Content -LiteralPath $invalidCsv -Encoding UTF8

        $ErrorActionPreference = "Continue"
        $invalidOutput = & $DotNet run --project .\importer -- $invalidCsv 2>&1
        $invalidExit = $LASTEXITCODE
        $ErrorActionPreference = $savedErrorPreference
        $visible = (($invalidOutput -join "`n") -match "(?i)line\s+3")
        Check (($invalidExit -ne 0) -and $visible) `
            "Invalid row is visible to a scheduler" `
            "expected non-zero exit and line 3 diagnostic; exit=$invalidExit output='$($invalidOutput -join ' | ')'"
    } finally {
        Remove-Item -LiteralPath $invalidCsv -Force -ErrorAction SilentlyContinue
    }
} finally {
    Pop-Location
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) regression test(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "All regression tests passed." -ForegroundColor Green
exit 0
