<?php
/**
 * Location ciphertext storage. POST is called by a device's own unattended
 * 5-minute check-in (device token only — it can only write its own location,
 * never read anyone's history). GET is for a logged-in human viewing history
 * (account session — can read any device on their account, never write).
 *
 * The server only ever handles opaque base64 ciphertext here: it has no key
 * to decrypt it and never tries to.
 */

declare(strict_types=1);

require __DIR__ . '/config.php';

switch ($_SERVER['REQUEST_METHOD']) {
    case 'POST':
        $deviceId = requireDeviceToken($pdo);
        $body = requestBody();
        $ciphertext = (string)($body['ciphertext'] ?? '');
        $capturedAt = (string)($body['capturedAt'] ?? '');

        if ($ciphertext === '' || $capturedAt === '') {
            sendResponse(['message' => 'ciphertext and capturedAt are required'], 400);
        }

        try {
            // The client always sends this already converted to UTC (see
            // ApiClient.submitLocation) -- setTimezone(UTC) here makes that
            // explicit rather than relying on the input string's own offset,
            // so what lands in this naive DATETIME column is unambiguous
            // regardless of how it was phrased.
            $capturedAtUtc = (new DateTime($capturedAt))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
        } catch (Exception) {
            sendResponse(['message' => 'capturedAt must be a valid ISO 8601 timestamp'], 400);
        }

        $pdo->prepare('INSERT INTO locations (device_id, ciphertext, captured_at) VALUES (?, ?, ?)')
            ->execute([$deviceId, $ciphertext, $capturedAtUtc]);

        $pdo->prepare('UPDATE devices SET last_seen_at = NOW() WHERE id = ?')->execute([$deviceId]);

        // Lazily purge old points for this device rather than running a cron
        // job — keeps retention bounded with no extra infrastructure.
        $pdo->prepare(
            'DELETE FROM locations WHERE device_id = ? AND captured_at < DATE_SUB(NOW(), INTERVAL ? DAY)'
        )->execute([$deviceId, LOCATION_RETENTION_DAYS]);

        sendResponse(['message' => 'Location stored'], 201);

    case 'GET':
        $accountId = requireAccountSession($pdo);
        $deviceId = (string)($_GET['deviceId'] ?? '');
        $limit = max(1, min(500, (int)($_GET['limit'] ?? 50)));

        if ($deviceId === '') {
            sendResponse(['message' => 'deviceId is required'], 400);
        }

        // Ownership check: this device must belong to the requesting account.
        $stmt = $pdo->prepare('SELECT id FROM devices WHERE id = ? AND account_id = ?');
        $stmt->execute([$deviceId, $accountId]);
        if ($stmt->fetch() === false) {
            sendResponse(['message' => 'Device not found'], 404);
        }

        $stmt = $pdo->prepare(
            'SELECT ciphertext, captured_at FROM locations
             WHERE device_id = ? ORDER BY captured_at DESC LIMIT ?'
        );
        $stmt->bindValue(1, $deviceId);
        $stmt->bindValue(2, $limit, PDO::PARAM_INT);
        $stmt->execute();
        $rows = array_reverse($stmt->fetchAll());

        $locations = array_map(static function (array $row): array {
            return [
                'ciphertext' => $row['ciphertext'],
                // captured_at is a naive DATETIME storing UTC wall-clock (see
                // the POST handler above) -- constructing without an explicit
                // UTC DateTimeZone here would instead interpret it using
                // whatever timezone this PHP server's date.timezone happens
                // to be set to, silently shifting every timestamp shown to
                // the app/web viewer by that server's UTC offset.
                'capturedAt' => (new DateTime($row['captured_at'], new DateTimeZone('UTC')))->format(DateTime::ATOM),
            ];
        }, $rows);

        sendResponse(['locations' => $locations]);

    default:
        sendResponse(['message' => 'Method not allowed'], 405);
}
