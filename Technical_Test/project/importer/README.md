# TestOps importer

Run from the project root:

```powershell
dotnet run --project .\importer -- .\data\test_export_2026-02.csv
```

The importer trims and uppercases identifiers, accepts the three timestamp
formats present in the station export, validates domain values, and treats a
blank station as `NULL` because the supplied database schema permits it. The
destination is `DATETIME2`, so timestamps ending in `Z` preserve their exported
wall-clock value rather than applying a timezone conversion that the schema
cannot retain.

## Re-runs and failures

`SerialNumber + AttemptNo` is the business key: the assignment defines the
attempt number as the sequence of tests for one board. The database enforces
that key, and each import runs in a serializable transaction. Re-running a file
therefore leaves the resulting data unchanged, including if two scheduled runs
overlap.

Exit codes are intended for a scheduler:

- `0`: all rows were processed; warnings may still describe resolved conflicts.
- `1`: the import failed and its database transaction was rolled back.
- `2`: valid rows were committed, but one or more rejected rows were printed to
  stderr with their source line and reason.

## Ambiguous records

When copies of the same board attempt disagree, **FAIL wins**. This is
deterministic regardless of input order and conservative for a quality KPI: a
contradictory record cannot turn evidence of a failed first attempt into a
first-pass success. If two conflicting records have the same result, a stable
canonical ordering breaks the tie.

The cost is a possible downward bias: an erroneous stale FAIL can override a
correct PASS. Each conflict is therefore printed with both source line numbers,
the chosen line, and the chosen result so production can investigate it rather
than mistaking the policy for certainty.
