<?php
/**
 * Verifies the account code + current TOTP code and, on success, issues a
 * short-lived interactive account session (used to view history and manage
 * devices — never used for the unattended 5-minute check-in, which uses its
 * own per-device token from devices.php instead).
 */

declare(strict_types=1);

require __DIR__ . '/config.php';
require __DIR__ . '/totp.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(['message' => 'Method not allowed'], 405);
}

$body = requestBody();
$code = strtolower(trim((string)($body['code'] ?? '')));
$totp = (string)($body['totp'] ?? '');

if ($code === '' || $totp === '') {
    sendResponse(['message' => 'Code and 6-digit code are required'], 400);
}

$codeLookup = hash_hmac('sha256', $code, CODE_LOOKUP_PEPPER);
$stmt = $pdo->prepare(
    'SELECT id, code_hash, code_salt, totp_secret_ciphertext, totp_secret_nonce FROM accounts WHERE code_lookup = ?'
);
$stmt->execute([$codeLookup]);
$account = $stmt->fetch();

if ($account === false || !password_verify($code, $account['code_hash'])) {
    sendResponse(['message' => 'Invalid code or verification code'], 401);
}

$encryptionKey = base64_decode(TOTP_ENCRYPTION_KEY_BASE64);
$totpSecret = sodium_crypto_secretbox_open(
    $account['totp_secret_ciphertext'],
    $account['totp_secret_nonce'],
    $encryptionKey
);

if ($totpSecret === false || !Totp::verify($totpSecret, $totp)) {
    sendResponse(['message' => 'Invalid code or verification code'], 401);
}

$sessionToken = newTokenHex();
$stmt = $pdo->prepare(
    'INSERT INTO account_sessions (id, account_id, token_hash, expires_at)
     VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))'
);
$stmt->execute([newUuid(), $account['id'], hashToken($sessionToken), ACCOUNT_SESSION_LIFETIME_SECONDS]);

sendResponse([
    'sessionToken' => $sessionToken,
    'salt' => $account['code_salt'],
]);
