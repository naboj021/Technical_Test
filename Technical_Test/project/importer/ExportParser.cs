using System.Globalization;
using Microsoft.VisualBasic.FileIO;

namespace TestOps.Importer;

public static class ExportParser
{
    private static readonly string[] ExpectedHeader =
        ["serial_number", "product_code", "station_code", "started_at", "result", "attempt_no"];

    private static readonly string[] DateFormats =
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss'Z'", "dd/MM/yyyy HH:mm:ss"];

    private static readonly HashSet<string> Products =
        ["PCA-1180", "PCA-2240", "PCA-3310", "PCA-4020"];

    private static readonly HashSet<string> Stations =
        ["ICT-01", "FCT-01", "AOI-02"];

    public static ParsedBatch Parse(string path)
    {
        using var parser = new TextFieldParser(path)
        {
            TextFieldType = FieldType.Delimited,
            HasFieldsEnclosedInQuotes = true,
            TrimWhiteSpace = false
        };
        parser.SetDelimiters(",");

        var header = parser.ReadFields() ?? [];
        if (!header.SequenceEqual(ExpectedHeader, StringComparer.OrdinalIgnoreCase))
            throw new InvalidDataException($"unexpected CSV header: {string.Join(',', header)}");

        var sessions = new Dictionary<(string SerialNumber, int AttemptNo), SourceSession>();
        var issues = new List<ImportIssue>();
        var duplicateCount = 0;
        var conflictCount = 0;
        var rejectionCount = 0;

        while (!parser.EndOfData)
        {
            var lineNumber = parser.LineNumber;
            try
            {
                var session = ParseRow(parser.ReadFields() ?? []);
                var key = (session.SerialNumber, session.AttemptNo);

                if (!sessions.TryGetValue(key, out var previous))
                {
                    sessions.Add(key, new SourceSession(session, lineNumber));
                }
                else if (previous.Session == session)
                {
                    duplicateCount++;
                }
                else
                {
                    conflictCount++;
                    var winner = ResolveConflict(previous.Session, session);
                    var winningLine = winner == previous.Session ? previous.LineNumber : lineNumber;
                    sessions[key] = new SourceSession(winner, winningLine);
                    issues.Add(new ImportIssue(
                        lineNumber,
                        "WARNING",
                        $"conflicts with line {previous.LineNumber} for {key.SerialNumber} attempt {key.AttemptNo}; " +
                        $"kept line {winningLine} ({winner.Result}) using the FAIL-wins rule"));
                }
            }
            catch (Exception ex) when (ex is InvalidDataException or FormatException or MalformedLineException)
            {
                rejectionCount++;
                issues.Add(new ImportIssue(lineNumber, "REJECT", ex.Message));
            }
        }

        return new ParsedBatch(
            sessions.Values.Select(value => value.Session).ToArray(),
            issues,
            duplicateCount,
            conflictCount,
            rejectionCount);
    }

    public static TestSession ParseRow(string[] fields)
    {
        if (fields.Length != ExpectedHeader.Length)
            throw new InvalidDataException($"expected 6 fields, found {fields.Length}");

        var serialNumber = fields[0].Trim().ToUpperInvariant();
        var productCode = fields[1].Trim().ToUpperInvariant();
        var stationCode = fields[2].Trim().ToUpperInvariant();
        var result = fields[4].Trim().ToUpperInvariant();

        if (serialNumber.Length is 0 or > 50)
            throw new InvalidDataException("serial number is empty or longer than 50 characters");
        if (!Products.Contains(productCode))
            throw new InvalidDataException($"unknown product '{productCode}'");
        if (stationCode.Length > 0 && !Stations.Contains(stationCode))
            throw new InvalidDataException($"unknown station '{stationCode}'");
        if (result is not ("PASS" or "FAIL"))
            throw new InvalidDataException($"invalid result '{result}'");
        if (!int.TryParse(fields[5].Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var attemptNo)
            || attemptNo <= 0)
            throw new InvalidDataException($"invalid attempt number '{fields[5]}'");

        // The destination is DATETIME2 and has no timezone. Preserve the wall-clock
        // value in all three station formats; the trailing Z is treated as export syntax.
        if (!DateTime.TryParseExact(
                fields[3].Trim(),
                DateFormats,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var startedAt))
            throw new InvalidDataException($"invalid timestamp '{fields[3]}'");

        return new TestSession(
            serialNumber,
            productCode,
            stationCode.Length == 0 ? null : stationCode,
            startedAt,
            result,
            attemptNo);
    }

    public static TestSession ResolveConflict(TestSession left, TestSession right)
    {
        if (left.SerialNumber != right.SerialNumber || left.AttemptNo != right.AttemptNo)
            throw new ArgumentException("Only records for the same board attempt can be resolved.");

        // Conservative quality reporting: contradictory evidence must not turn a
        // failed attempt into a pass. This is deterministic regardless of file order.
        if (left.Result == "FAIL" && right.Result != "FAIL") return left;
        if (right.Result == "FAIL" && left.Result != "FAIL") return right;

        return string.CompareOrdinal(left.CanonicalValue, right.CanonicalValue) <= 0 ? left : right;
    }

    private sealed record SourceSession(TestSession Session, long LineNumber);
}
