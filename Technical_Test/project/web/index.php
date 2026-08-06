<?php
declare(strict_types=1);
require __DIR__ . '/db.php';

$from = $_GET['from'] ?? '2026-01-01';
$to   = $_GET['to']   ?? '2026-01-31';

try {
    $pdo    = testops_connection();
    $kpi    = first_pass_yield($pdo, $from, $to);
    $daily  = daily_volume($pdo, $from, $to);
    $error  = null;
} catch (Throwable $e) {
    $kpi = $daily = [];
    $error = $e->getMessage();
}
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>TestOps — yield</title>
    <style>
        body { font-family: system-ui, sans-serif; margin: 2rem; color: #1c2733; }
        h1 { font-size: 1.25rem; }
        .kpi { font-size: 3rem; font-weight: 600; margin: .5rem 0; }
        .meta { color: #667; margin-bottom: 2rem; }
        table { border-collapse: collapse; }
        th, td { padding: .4rem .9rem; border-bottom: 1px solid #dde; text-align: right; }
        th:first-child, td:first-child { text-align: left; }
        .err { background: #fee; border: 1px solid #d99; padding: 1rem; }
    </style>
</head>
<body>
<h1>First pass yield</h1>

<?php if ($error): ?>
    <p class="err"><?= htmlspecialchars($error) ?></p>
<?php else: ?>
    <div class="kpi"><?= htmlspecialchars((string) $kpi['FirstPassYieldPct']) ?>%</div>
    <div class="meta">
        <?= (int) $kpi['UnitsPassed'] ?> passed of <?= (int) $kpi['UnitsTested'] ?> tested
        &middot; <?= htmlspecialchars($from) ?> to <?= htmlspecialchars($to) ?>
    </div>

    <table>
        <tr><th>Date</th><th>Tested</th><th>Failed</th></tr>
        <?php foreach ($daily as $row): ?>
            <tr>
                <td><?= htmlspecialchars((string) $row['TestDate']) ?></td>
                <td><?= (int) $row['UnitsTested'] ?></td>
                <td><?= (int) $row['UnitsFailed'] ?></td>
            </tr>
        <?php endforeach; ?>
    </table>
<?php endif; ?>
</body>
</html>
