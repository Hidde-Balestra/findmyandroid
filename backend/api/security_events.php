<?php
/**
 * Security snapshots: a front-camera photo + location logged after too many
 * failed account-code/TOTP attempts on a device (see the app's
 * SecurityCaptureService and FailedAttemptTracker). Documented, opt-in
 * feature — the threshold is configurable in-app (0 disables it) and
 * requesting camera permission is an explicit, visible step, not a hidden
 * capability.
 *
 * POST uses the device's own scoped token (same as locations.php) so it
 * works from the unattended flow with no interactive session available.
 * GET uses an account session, same ownership rules as every other
 * per-device read. The server only ever handles opaque ciphertext — it has
 * no key to view a photo or decrypt a location.
 */

declare(strict_types=1);

require __DIR__ . '/config.php';

switch ($_SERVER['REQUEST_METHOD']) {
    case 'POST':
        $deviceId = requireDeviceToken($pdo);
        $body = requestBody();
        $photoCiphertext = $body['photoCiphertext'] ?? null;
        $locationCiphertext = $body['locationCiphertext'] ?? null;
        $capturedAt = (string)($body['capturedAt'] ?? '');

        if ($photoCiphertext === null && $locationCiphertext === null) {
            sendResponse(['message' => 'photoCiphertext and/or locationCiphertext is required'], 400);
        }
        if ($capturedAt === '') {
            sendResponse(['message' => 'capturedAt is required'], 400);
        }

        try {
            // The client always sends this already converted to UTC (see
            // ApiClient.submitSecurityEvent) -- setTimezone(UTC) here makes
            // that explicit rather than relying on the input string's own
            // offset, so what lands in this naive DATETIME column is
            // unambiguous regardless of how it was phrased.
            $capturedAtUtc = (new DateTime($capturedAt))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
        } catch (Exception) {
            sendResponse(['message' => 'capturedAt must be a valid ISO 8601 timestamp'], 400);
        }

        $pdo->prepare(
            'INSERT INTO security_events (device_id, photo_ciphertext, location_ciphertext, captured_at)
             VALUES (?, ?, ?, ?)'
        )->execute([$deviceId, $photoCiphertext, $locationCiphertext, $capturedAtUtc]);

        // Lazily purge old events rather than running a cron job.
        $pdo->prepare(
            'DELETE FROM security_events WHERE device_id = ? AND captured_at < DATE_SUB(NOW(), INTERVAL ? DAY)'
        )->execute([$deviceId, SECURITY_EVENT_RETENTION_DAYS]);

        sendResponse(['message' => 'Security event stored'], 201);

    case 'GET':
        $accountId = requireAccountSession($pdo);
        $deviceId = (string)($_GET['deviceId'] ?? '');
        $limit = max(1, min(100, (int)($_GET['limit'] ?? 20)));

        if ($deviceId === '') {
            sendResponse(['message' => 'deviceId is required'], 400);
        }

        $stmt = $pdo->prepare('SELECT id FROM devices WHERE id = ? AND account_id = ?');
        $stmt->execute([$deviceId, $accountId]);
        if ($stmt->fetch() === false) {
            sendResponse(['message' => 'Device not found'], 404);
        }

        $stmt = $pdo->prepare(
            'SELECT photo_ciphertext, location_ciphertext, captured_at FROM security_events
             WHERE device_id = ? ORDER BY captured_at DESC LIMIT ?'
        );
        $stmt->bindValue(1, $deviceId);
        $stmt->bindValue(2, $limit, PDO::PARAM_INT);
        $stmt->execute();

        $events = array_map(static function (array $row): array {
            return [
                'photoCiphertext' => $row['photo_ciphertext'],
                'locationCiphertext' => $row['location_ciphertext'],
                // captured_at is a naive DATETIME storing UTC wall-clock (see
                // the POST handler above) -- constructing without an explicit
                // UTC DateTimeZone here would instead interpret it using
                // whatever timezone this PHP server's date.timezone happens
                // to be set to, silently shifting every timestamp shown to
                // the app/web viewer by that server's UTC offset.
                'capturedAt' => (new DateTime($row['captured_at'], new DateTimeZone('UTC')))->format(DateTime::ATOM),
            ];
        }, $stmt->fetchAll());

        sendResponse(['events' => $events]);

    default:
        sendResponse(['message' => 'Method not allowed'], 405);
}
