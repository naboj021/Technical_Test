# Technical note

The first-pass dashboard was calculating PASS test attempts divided by all test
attempts, rather than boards that passed attempt one divided by boards tested.
That allowed a repaired board's later PASS to improve first-pass yield. Its
`BETWEEN @FromDate AND @ToDate` predicate also treated the end date as midnight,
excluding nearly all tests on 31 January. The original calculation therefore
reported 1,878 PASS attempts from 2,044 included attempts, or 91.88%. Including
the full month gives 2,309 attempts and 2,043 PASS attempts (88.48%); applying
the business definition gives 1,879 first-attempt passes from 2,139 boards,
which is **87.84%** and matches production. Final yield uses the same cohort and
counts 2,043 boards with any PASS by month end, or **95.51%**.

The reporting procedures now use board-level cohorts and half-open date ranges.
The PHP page displays first-pass and final yield side by side. The importer now
uses a real CSV parser, normalizes identifiers, handles all three timestamp
formats in the supplied export, validates domain values, and reports every
rejected or conflicting source line. A database unique constraint on
`SerialNumber + AttemptNo`, locked upserts, and a serializable transaction make
both sequential and overlapping re-runs idempotent. Valid rows are committed
when malformed rows are present, but the process returns exit code 2 so a
scheduler cannot mistake that partial import for complete success.

The 1,223-row February export normalizes to 1,165 unique attempts. It contains
51 exact duplicate rows and seven conflicting occurrences covering six board
attempts. For contradictory records, **FAIL wins**. This deterministic,
order-independent rule is conservative: uncertain evidence cannot inflate a
quality KPI. Its cost is possible downward bias if a stale FAIL is wrong, so
every decision is emitted with source line numbers for investigation.

Automated regression tests were committed before the fixes and fail against the
supplied code. They now cover the January figures, repaired boards, end-date
boundaries, the real export, repeated and parallel imports, conflict outcomes,
and visible rejection diagnostics. With more time I would persist import-batch
and rejection audit records, agree the `Z` timestamp semantics with the station
owners, add CI using an ephemeral SQL Server, and alert on partial imports.
