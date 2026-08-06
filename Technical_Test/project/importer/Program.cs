using System.Globalization;
using Dapper;
using Microsoft.Data.SqlClient;

namespace TestOps.Importer;

/// <summary>
/// Loads a station export file into dbo.TestSessions.
///
/// Run:  dotnet run -- ../data/test_export_2026-02.csv
/// </summary>
public static class Program
{
    private static string ConnectionString =>
        Environment.GetEnvironmentVariable("TESTOPS_CONNECTION")
        ?? "Server=localhost,1433;Database=TestOps;User Id=sa;Password=Str0ng!Passw0rd;TrustServerCertificate=True";

    public static int Main(string[] args)
    {
        // Pin the culture so log output looks the same on every machine,
        // whatever the operator has set their regional options to.
        CultureInfo.DefaultThreadCurrentCulture = new CultureInfo("en-US");

        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: dotnet run -- <path-to-export.csv>");
            return 1;
        }

        var path = args[0];
        if (!File.Exists(path))
        {
            Console.Error.WriteLine($"file not found: {path}");
            return 1;
        }

        var inserted = Import(path);
        Console.WriteLine($"Import complete. {inserted} rows written.");
        return 0;
    }

    private static int Import(string path)
    {
        using var connection = new SqlConnection(ConnectionString);
        connection.Open();

        var inserted = 0;
        var lineNumber = 0;

        foreach (var line in File.ReadLines(path))
        {
            lineNumber++;

            if (lineNumber == 1)
            {
                continue; // header
            }

            try
            {
                var parts = line.Split(',');

                var session = new TestSession
                {
                    SerialNumber = parts[0],
                    ProductCode  = parts[1],
                    StationCode  = parts[2],
                    StartedAt    = DateTime.Parse(parts[3]),
                    Result       = parts[4],
                    AttemptNo    = int.Parse(parts[5])
                };

                connection.Execute(
                    @"INSERT INTO dbo.TestSessions
                          (SerialNumber, ProductCode, StationCode, StartedAt, Result, AttemptNo)
                      VALUES
                          (@SerialNumber, @ProductCode, @StationCode, @StartedAt, @Result, @AttemptNo);",
                    session);

                inserted++;
            }
            catch
            {
                // Row could not be handled. Move on to the next one.
            }
        }

        return inserted;
    }
}

public sealed class TestSession
{
    public string SerialNumber { get; set; } = string.Empty;
    public string ProductCode { get; set; } = string.Empty;
    public string? StationCode { get; set; }
    public DateTime StartedAt { get; set; }
    public string Result { get; set; } = string.Empty;
    public int AttemptNo { get; set; }
}
