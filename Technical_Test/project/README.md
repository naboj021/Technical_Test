# TestOps production reporting

The supplied setup guide is `../README.docx`. With Docker Desktop running and
.NET 8 on `PATH`, run these commands from this directory:

```powershell
docker compose up -d
powershell -ExecutionPolicy Bypass -File .\db\setup.ps1
powershell -ExecutionPolicy Bypass -File .\tests\run-regression.ps1
```

The dashboard is available at <http://localhost:8080>. Its default January 2026
view shows first-pass yield and final yield for the same cohort of boards. Final
yield is measured **as of the reporting period end**: a repair PASS recorded
later does not retroactively change a closed period.

Import the supplied station export with:

```powershell
dotnet run --project .\importer -- .\data\test_export_2026-02.csv
```

The command is safe to repeat. See `importer/README.md` for normalization,
conflict handling, transaction behaviour, and scheduler exit codes. The full
regression command resets the database to the supplied January fixture, so run
it only in this local test environment.

Focused parser and conflict-policy unit tests can be run without Docker:

```powershell
dotnet test .\importer.tests\Importer.Tests.csproj
```

See `NOTE.md` for the findings, decisions, verification figures, and suggested
next steps.
