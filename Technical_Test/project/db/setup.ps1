# Creates the database, loads the fixture and installs the procedures.
# Run once from the repo root, after: docker compose up -d
#   powershell -ExecutionPolicy Bypass -File .\db\setup.ps1

$ErrorActionPreference = "Stop"
$container = "testops-sql"
$password  = "Str0ng!Passw0rd"

# image layout differs between mssql versions
$sqlcmd = $null
foreach ($p in @("/opt/mssql-tools18/bin/sqlcmd", "/opt/mssql-tools/bin/sqlcmd")) {
    docker exec $container test -x $p 2>$null
    if ($LASTEXITCODE -eq 0) { $sqlcmd = $p; break }
}
if (-not $sqlcmd) { throw "sqlcmd not found inside $container" }

Write-Host "waiting for sql server..."
for ($i = 0; $i -lt 40; $i++) {
    docker exec $container $sqlcmd -S localhost -U sa -P $password -C -Q "SELECT 1" *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 3
}

foreach ($f in @("01_schema.sql", "02_seed.sql", "03_procs.sql")) {
    Write-Host "applying $f"
    docker exec $container $sqlcmd -S localhost -U sa -P $password -C -d master -i "/db/$f"
    if ($LASTEXITCODE -ne 0) { throw "failed on $f" }
}

Write-Host ""
Write-Host "sanity check - expect FirstPassYieldPct = 91.88"
docker exec $container $sqlcmd -S localhost -U sa -P $password -C -d TestOps `
    -Q "EXEC dbo.usp_GetFirstPassYield @FromDate='2026-01-01', @ToDate='2026-01-31';"
