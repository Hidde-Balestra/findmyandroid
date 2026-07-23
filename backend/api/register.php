<?php
/**
 * Creates a brand-new, fully anonymous account: a random high-entropy
 * account code (the only credential — shown once, never recoverable) plus
 * a TOTP second factor. No email, phone number, or any other identifying
 * field is ever collected.
 */

declare(strict_types=1);

require __DIR__ . '/config.php';
require __DIR__ . '/totp.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(['message' => 'Method not allowed'], 405);
}

// 20 random bytes (160 bits) as hex, grouped for readability. Case-
// insensitive on login (see login.php) so it's easy to type from a
// password manager on a phone keyboard.
$codeBytes = bin2hex(random_bytes(20));
$code = implode('-', str_split($codeBytes, 5));

$salt = base64_encode(random_bytes(16));

$totpSecret = Totp::generateSecret();
$totpNonce = random_bytes(SODIUM_CRYPTO_SECRETBOX_NONCEBYTES);
$encryptionKey = base64_decode(TOTP_ENCRYPTION_KEY_BASE64);
$totpCiphertext = sodium_crypto_secretbox($totpSecret, $totpNonce, $encryptionKey);

// Normalized to lowercase everywhere it's hashed/compared, since users type
// this in from a password manager and mobile keyboards love to
// autocapitalize — the code itself is always generated lowercase.
$accountId = newUuid();
$codeLookup = hash_hmac('sha256', strtolower($code), CODE_LOOKUP_PEPPER);
$codeHash = password_hash(strtolower($code), PASSWORD_ARGON2ID);

$stmt = $pdo->prepare(
    'INSERT INTO accounts (id, code_lookup, code_hash, code_salt, totp_secret_ciphertext, totp_secret_nonce)
     VALUES (?, ?, ?, ?, ?, ?)'
);
$stmt->execute([$accountId, $codeLookup, $codeHash, $salt, $totpCiphertext, $totpNonce]);

sendResponse([
    'code' => $code,
    'salt' => $salt,
    'totpUri' => Totp::provisioningUri($totpSecret, substr($accountId, 0, 8), TOTP_ISSUER),
]);
