<?php
/**
 * "Play sound" command queue. POST (account session) queues a command from
 * the web viewer or the app's device-management screen. GET (device token)
 * is polled by that device's own 5-minute check-in — there is deliberately
 * no push/WebSocket channel here, so ringing can take up to 5 minutes to
 * trigger; see the README for why that trade-off was chosen.
 */

declare(strict_types=1);

require __DIR__ . '/config.php';

switch ($_SERVER['REQUEST_METHOD']) {
    case 'POST':
        $accountId = requireAccountSession($pdo);
        $body = requestBody();
        $deviceId = (string)($body['deviceId'] ?? '');
        if ($deviceId === '') {
            sendResponse(['message' => 'deviceId is required'], 400);
        }

        $stmt = $pdo->prepare('SELECT id FROM devices WHERE id = ? AND account_id = ?');
        $stmt->execute([$deviceId, $accountId]);
        if ($stmt->fetch() === false) {
            sendResponse(['message' => 'Device not found'], 404);
        }

        // Don't stack duplicate pending commands if the user taps twice.
        $stmt = $pdo->prepare("SELECT id FROM ring_commands WHERE device_id = ? AND status = 'pending'");
        $stmt->execute([$deviceId]);
        if ($stmt->fetch() === false) {
            $pdo->prepare('INSERT INTO ring_commands (device_id) VALUES (?)')->execute([$deviceId]);
        }

        sendResponse(['message' => 'Sound queued'], 201);

    case 'GET':
        $deviceId = requireDeviceToken($pdo);

        $stmt = $pdo->prepare(
            "SELECT id FROM ring_commands
             WHERE device_id = ? AND status = 'pending'
               AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
             ORDER BY created_at ASC LIMIT 1"
        );
        $stmt->execute([$deviceId, RING_COMMAND_MAX_AGE_DAYS]);
        $command = $stmt->fetch();

        if ($command === false) {
            sendResponse(['ring' => false]);
        }

        $pdo->prepare("UPDATE ring_commands SET status = 'delivered', delivered_at = NOW() WHERE id = ?")
            ->execute([$command['id']]);

        sendResponse(['ring' => true]);

    default:
        sendResponse(['message' => 'Method not allowed'], 405);
}
