using System.Globalization;

namespace TestOps.Importer;

public static class Program
{
    private static string ConnectionString =>
        Environment.GetEnvironmentVariable("TESTOPS_CONNECTION")
        ?? "Server=localhost,1433;Database=TestOps;User Id=sa;Password=Str0ng!Passw0rd;TrustServerCertificate=True";

    public static int Main(string[] args)
    {
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;

        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: dotnet run -- <path-to-export.csv>");
            return 1;
        }

        if (!File.Exists(args[0]))
        {
            Console.Error.WriteLine($"file not found: {args[0]}");
            return 1;
        }

        try
        {
            var batch = ExportParser.Parse(args[0]);
            foreach (var issue in batch.Issues)
                Console.Error.WriteLine(issue);

            var result = ImportService.Import(ConnectionString, batch.Sessions);
            Console.WriteLine(
                $"Import complete. {result.Inserted} inserted, {result.Updated} updated, " +
                $"{result.Unchanged} unchanged; {batch.DuplicateCount} duplicate rows ignored, " +
                $"{batch.ConflictCount} conflicts resolved, {batch.RejectionCount} rows rejected.");

            // A scheduler must be able to distinguish a complete import from
            // one where rows were rejected, even though valid rows were saved.
            return batch.RejectionCount == 0 ? 0 : 2;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Import failed; transaction rolled back: {ex.Message}");
            return 1;
        }
    }
}
