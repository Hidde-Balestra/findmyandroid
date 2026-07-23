<?php
/**
 * Device pairing and management. All of this requires an interactive
 * account session (code + TOTP) — pairing a device is something a human
 * does once, not something the unattended check-in ever calls.
 */

declare(strict_types=1);

require __DIR__ . '/config.php';

$accountId = requireAccountSession($pdo);

switch ($_SERVER['REQUEST_METHOD']) {
    case 'POST':
        $body = requestBody();
        $label = trim((string)($body['label'] ?? ''));
        if ($label === '') {
            sendResponse(['message' => 'label is required'], 400);
        }

        $deviceId = newUuid();
        $deviceToken = newTokenHex();

        $stmt = $pdo->prepare(
            'INSERT INTO devices (id, account_id, label, token_hash) VALUES (?, ?, ?, ?)'
        );
        $stmt->execute([$deviceId, $accountId, $label, hashToken($deviceToken)]);

        sendResponse(['deviceId' => $deviceId, 'deviceToken' => $deviceToken], 201);

    case 'GET':
        $stmt = $pdo->prepare(
            'SELECT id, label, last_seen_at FROM devices WHERE account_id = ? ORDER BY created_at ASC'
        );
        $stmt->execute([$accountId]);
        $devices = array_map(static function (array $row): array {
            return [
                'id' => $row['id'],
                'label' => $row['label'],
                'lastSeenAt' => $row['last_seen_at'] !== null
                    ? (new DateTime($row['last_seen_at']))->format(DateTime::ATOM)
                    : null,
            ];
        }, $stmt->fetchAll());

        sendResponse(['devices' => $devices]);

    case 'DELETE':
        $deviceId = (string)($_GET['deviceId'] ?? '');
        if ($deviceId === '') {
            sendResponse(['message' => 'deviceId is required'], 400);
        }
        $stmt = $pdo->prepare('DELETE FROM devices WHERE id = ? AND account_id = ?');
        $stmt->execute([$deviceId, $accountId]);
        sendResponse(['message' => 'Device removed']);

    default:
        sendResponse(['message' => 'Method not allowed'], 405);
}
