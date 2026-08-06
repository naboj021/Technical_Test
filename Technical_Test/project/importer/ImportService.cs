using Dapper;
using Microsoft.Data.SqlClient;

namespace TestOps.Importer;

public static class ImportService
{
    public static ImportResult Import(string connectionString, IReadOnlyCollection<TestSession> sessions)
    {
        using var connection = new SqlConnection(connectionString);
        connection.Open();
        using var transaction = connection.BeginTransaction(System.Data.IsolationLevel.Serializable);

        var inserted = 0;
        var updated = 0;
        var unchanged = 0;

        try
        {
            foreach (var session in sessions)
            {
                var existing = connection.QuerySingleOrDefault<StoredSession>(
                    @"SELECT SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo
                      FROM dbo.TestSessions WITH (UPDLOCK, HOLDLOCK)
                      WHERE SerialNumber = @SerialNumber AND AttemptNo = @AttemptNo;",
                    session,
                    transaction);

                if (existing is null)
                {
                    connection.Execute(
                        @"INSERT dbo.TestSessions
                              (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo)
                          VALUES
                              (@SerialNumber, @ProductCode, @StationCode, @StartedAt, @Result, @AttemptNo);",
                        session,
                        transaction);
                    inserted++;
                    continue;
                }

                var stored = existing.ToTestSession();
                if (stored == session)
                {
                    unchanged++;
                    continue;
                }

                var winner = ExportParser.ResolveConflict(stored, session);
                if (winner == stored)
                {
                    unchanged++;
                    continue;
                }

                connection.Execute(
                    @"UPDATE dbo.TestSessions
                      SET ProductCode = @ProductCode,
                          StationCode = @StationCode,
                          StartedAt = @StartedAt,
                          Result = @Result
                      WHERE SerialNumber = @SerialNumber AND AttemptNo = @AttemptNo;",
                    winner,
                    transaction);
                updated++;
            }

            transaction.Commit();
            return new ImportResult(inserted, updated, unchanged);
        }
        catch
        {
            transaction.Rollback();
            throw;
        }
    }

    private sealed class StoredSession
    {
        public string SerialNumber { get; init; } = string.Empty;
        public string ProductCode { get; init; } = string.Empty;
        public string? StationCode { get; init; }
        public DateTime StartedAt { get; init; }
        public string Result { get; init; } = string.Empty;
        public int AttemptNo { get; init; }

        public TestSession ToTestSession() =>
            new(SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo);
    }
}
