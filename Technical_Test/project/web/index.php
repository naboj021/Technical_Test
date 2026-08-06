<?php
declare(strict_types=1);
require __DIR__ . '/db.php';

$from = $_GET['from'] ?? '2026-01-01';
$to   = $_GET['to']   ?? '2026-01-31';

try {
    $pdo    = testops_connection();
    $kpi    = first_pass_yield($pdo, $from, $to);
    $final  = final_yield($pdo, $from, $to);
    $daily  = daily_volume($pdo, $from, $to);
    $error  = null;
} catch (Throwable $e) {
    $kpi = $final = $daily = [];
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
        .kpis { display: flex; gap: 3rem; flex-wrap: wrap; margin: 1rem 0 .5rem; }
        .kpi-card { min-width: 15rem; }
        .kpi-label { font-weight: 600; }
        .kpi { font-size: 3rem; font-weight: 600; margin: .25rem 0; }
        .meta { color: #667; margin-bottom: 2rem; }
        table { border-collapse: collapse; }
        th, td { padding: .4rem .9rem; border-bottom: 1px solid #dde; text-align: right; }
        th:first-child, td:first-child { text-align: left; }
        .err { background: #fee; border: 1px solid #d99; padding: 1rem; }
    </style>
</head>
<body>
<h1>Production yield</h1>

<?php if ($error): ?>
    <p class="err"><?= htmlspecialchars($error) ?></p>
<?php else: ?>
    <div class="kpis">
        <section class="kpi-card">
            <div class="kpi-label">First pass yield</div>
            <div class="kpi"><?= htmlspecialchars((string) $kpi['FirstPassYieldPct']) ?>%</div>
        </section>
        <section class="kpi-card">
            <div class="kpi-label">Final yield</div>
            <div class="kpi"><?= htmlspecialchars((string) $final['FinalYieldPct']) ?>%</div>
        </section>
    </div>
    <div class="meta">
        First pass: <?= (int) $kpi['UnitsPassed'] ?> of <?= (int) $kpi['UnitsTested'] ?>
        &middot; Final: <?= (int) $final['UnitsPassed'] ?> of <?= (int) $final['UnitsTested'] ?>
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
