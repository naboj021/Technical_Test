<?php
declare(strict_types=1);

function testops_connection(): PDO
{
    $host = getenv('TESTOPS_HOST') ?: 'localhost';
    $db   = getenv('TESTOPS_DB') ?: 'TestOps';
    $user = getenv('TESTOPS_USER') ?: 'sa';
    $pass = getenv('TESTOPS_PASSWORD') ?: '';

    $pdo = new PDO("dblib:host={$host}:1433;dbname={$db}", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

    return $pdo;
}

function first_pass_yield(PDO $pdo, string $from, string $to): array
{
    $stmt = $pdo->prepare("EXEC dbo.usp_GetFirstPassYield @FromDate = ?, @ToDate = ?");
    $stmt->execute([$from, $to]);

    return $stmt->fetch() ?: ['UnitsTested' => 0, 'UnitsPassed' => 0, 'FirstPassYieldPct' => 0];
}

function final_yield(PDO $pdo, string $from, string $to): array
{
    $stmt = $pdo->prepare("EXEC dbo.usp_GetFinalYield @FromDate = ?, @ToDate = ?");
    $stmt->execute([$from, $to]);

    return $stmt->fetch() ?: ['UnitsTested' => 0, 'UnitsPassed' => 0, 'FinalYieldPct' => 0];
}

function daily_volume(PDO $pdo, string $from, string $to): array
{
    $stmt = $pdo->prepare("EXEC dbo.usp_GetDailyVolume @FromDate = ?, @ToDate = ?");
    $stmt->execute([$from, $to]);

    return $stmt->fetchAll();
}
