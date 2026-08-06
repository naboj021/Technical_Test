namespace TestOps.Importer;

public sealed record TestSession(
    string SerialNumber,
    string ProductCode,
    string? StationCode,
    DateTime StartedAt,
    string Result,
    int AttemptNo)
{
    public string CanonicalValue =>
        $"{ProductCode}|{StationCode ?? string.Empty}|{StartedAt:yyyy-MM-dd HH:mm:ss}|{Result}";
}

public sealed record ImportIssue(long LineNumber, string Severity, string Message)
{
    public override string ToString() => $"{Severity} line {LineNumber}: {Message}";
}

public sealed record ParsedBatch(
    IReadOnlyCollection<TestSession> Sessions,
    IReadOnlyList<ImportIssue> Issues,
    int DuplicateCount,
    int ConflictCount,
    int RejectionCount);

public sealed record DatabaseConflict(
    TestSession Existing,
    TestSession Incoming,
    TestSession Resolved,
    bool WasUpdated)
{
    public override string ToString() =>
        $"WARNING database conflict for {Incoming.SerialNumber} attempt {Incoming.AttemptNo}: " +
        $"existing={Existing.Result}, incoming={Incoming.Result}, resolved={Resolved.Result} " +
        $"using the FAIL-wins rule ({(WasUpdated ? "updated" : "kept existing")})";
}

public sealed record ImportResult(
    int Inserted,
    int Updated,
    int Unchanged,
    IReadOnlyList<DatabaseConflict> Conflicts)
{
    public int UpdatedDueToConflict => Conflicts.Count(conflict => conflict.WasUpdated);
}
