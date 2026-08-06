using TestOps.Importer;
using Xunit;

namespace TestOps.Importer.Tests;

public sealed class ExportParserTests
{
    public static TheoryData<string> SupportedTimestamps => new()
    {
        "2026-02-03 14:05:06",
        "2026-02-03T14:05:06Z",
        "03/02/2026 14:05:06"
    };

    [Theory]
    [MemberData(nameof(SupportedTimestamps))]
    public void ParseRow_accepts_all_export_timestamp_formats(string timestamp)
    {
        var session = ExportParser.ParseRow(Row(startedAt: timestamp));

        Assert.Equal(new DateTime(2026, 2, 3, 14, 5, 6), session.StartedAt);
        Assert.Equal(DateTimeKind.Unspecified, session.StartedAt.Kind);
    }

    [Fact]
    public void ParseRow_normalizes_codes_and_allows_blank_station()
    {
        var session = ExportParser.ParseRow(Row(
            serial: " sn-001 ", product: " pca-1180 ", station: " ", result: " pass "));

        Assert.Equal("SN-001", session.SerialNumber);
        Assert.Equal("PCA-1180", session.ProductCode);
        Assert.Null(session.StationCode);
        Assert.Equal("PASS", session.Result);
    }

    [Theory]
    [InlineData("SN-001", "UNKNOWN", "ICT-01", "PASS", "1")]
    [InlineData("SN-001", "PCA-1180", "UNKNOWN", "PASS", "1")]
    [InlineData("SN-001", "PCA-1180", "ICT-01", "MAYBE", "1")]
    [InlineData("SN-001", "PCA-1180", "ICT-01", "PASS", "0")]
    [InlineData("SN-001", "PCA-1180", "ICT-01", "PASS", "1.5")]
    public void ParseRow_rejects_invalid_domain_values(
        string serial, string product, string station, string result, string attempt)
    {
        Assert.Throws<InvalidDataException>(() =>
            ExportParser.ParseRow(Row(serial, product, station, result: result, attempt: attempt)));
    }

    [Fact]
    public void ParseRow_rejects_invalid_timestamp_and_column_count()
    {
        Assert.Throws<InvalidDataException>(() =>
            ExportParser.ParseRow(Row(startedAt: "2026/02/03")));
        Assert.Throws<InvalidDataException>(() =>
            ExportParser.ParseRow(["too", "few"]));
    }

    [Fact]
    public void Parse_supports_quoted_fields_and_counts_exact_duplicates()
    {
        var batch = ParseCsv(
            "\"sn-001\",\"PCA-1180\",\"ICT-01\",\"2026-02-03 14:05:06\",\"PASS\",\"1\"",
            "SN-001,PCA-1180,ICT-01,2026-02-03 14:05:06,PASS,1");

        Assert.Single(batch.Sessions);
        Assert.Equal(1, batch.DuplicateCount);
        Assert.Empty(batch.Issues);
    }

    [Fact]
    public void Parse_reports_rejected_rows_and_continues()
    {
        var batch = ParseCsv(
            "SN-BAD,PCA-1180,ICT-01,not-a-date,PASS,1",
            "SN-GOOD,PCA-1180,ICT-01,2026-02-03 14:05:06,PASS,1");

        Assert.Single(batch.Sessions);
        Assert.Equal(1, batch.RejectionCount);
        Assert.Contains(batch.Issues, issue => issue.Severity == "REJECT" && issue.LineNumber == 2);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Parse_resolves_conflicts_to_fail_regardless_of_order(bool failFirst)
    {
        const string pass = "SN-001,PCA-1180,ICT-01,2026-02-03 14:05:06,PASS,1";
        const string fail = "SN-001,PCA-1180,ICT-01,2026-02-03 14:06:06,FAIL,1";

        var batch = ParseCsv(failFirst ? [fail, pass] : [pass, fail]);

        Assert.Single(batch.Sessions);
        Assert.Equal("FAIL", batch.Sessions.Single().Result);
        Assert.Equal(1, batch.ConflictCount);
        Assert.Contains(batch.Issues, issue => issue.Message.Contains("FAIL-wins"));
    }

    [Fact]
    public void Parse_keeps_different_attempt_numbers()
    {
        var batch = ParseCsv(
            "SN-001,PCA-1180,ICT-01,2026-02-03 14:05:06,FAIL,1",
            "SN-001,PCA-1180,ICT-01,2026-02-03 15:05:06,PASS,2");

        Assert.Equal(2, batch.Sessions.Count);
        Assert.Equal(0, batch.ConflictCount);
    }

    private static string[] Row(
        string serial = "SN-001",
        string product = "PCA-1180",
        string station = "ICT-01",
        string startedAt = "2026-02-03 14:05:06",
        string result = "PASS",
        string attempt = "1") =>
        [serial, product, station, startedAt, result, attempt];

    private static ParsedBatch ParseCsv(params string[] rows)
    {
        var path = Path.Combine(Path.GetTempPath(), $"testops-parser-{Guid.NewGuid():N}.csv");
        try
        {
            File.WriteAllLines(path,
                ["serial_number,product_code,station_code,started_at,result,attempt_no", .. rows]);
            return ExportParser.Parse(path);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
