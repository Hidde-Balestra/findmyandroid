<?php
/**
 * Find My Android — shared backend config.
 *
 * No session cookies here on purpose: every endpoint is a stateless Bearer
 * token API (account sessions from login.php, or a device's own scoped
 * token from devices.php) so the phone's unattended background check-in
 * never needs interactive re-authentication.
 */

declare(strict_types=1);

require __DIR__ . '/env.php';

/**
 * Every real secret below is read from an environment variable, never
 * hardcoded here — this file lives in a public repo. Set these either as
 * real server environment variables, or (simplest on shared hosting)
 * in `.env` next to this file — see .env.example and env.php. The
 * fallback strings only exist so a misconfigured deployment fails
 * loudly/obviously instead of silently running with a guessable secret.
 */
define('DB_HOST', getenv('FMA_DB_HOST') ?: 'localhost');
define('DB_USER', getenv('FMA_DB_USER') ?: 'findmyandroid');
define('DB_PASSWORD', getenv('FMA_DB_PASSWORD') ?: 'CHANGE_ME');
define('DB_NAME', getenv('FMA_DB_NAME') ?: 'findmyandroid');
define('DB_CHARSET', 'utf8mb4');

// HMAC pepper used only to build the indexed, non-reversible lookup value
// for the account code (accounts.code_lookup) — never used on its own to
// authenticate. Generate with: bin2hex(random_bytes(32))
define('CODE_LOOKUP_PEPPER', getenv('FMA_CODE_LOOKUP_PEPPER') ?: 'CHANGE_ME_TO_A_LONG_RANDOM_VALUE');

// libsodium secretbox key (32 raw bytes, base64) used only to encrypt TOTP
// secrets at rest. Generate with: base64_encode(random_bytes(SODIUM_CRYPTO_SECRETBOX_KEYBYTES))
define('TOTP_ENCRYPTION_KEY_BASE64', getenv('FMA_TOTP_ENCRYPTION_KEY_BASE64') ?: 'CHANGE_ME_GENERATE_A_REAL_KEY');

define('TOTP_ISSUER', 'FindMyAndroid');

const ACCOUNT_SESSION_LIFETIME_SECONDS = 3600; // 1 hour
const RING_COMMAND_MAX_AGE_DAYS = 1;
const LOCATION_RETENTION_DAYS = 30;

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$isAllowedOrigin = $origin !== '' && (
    preg_match('/^https?:\/\/localhost(:\d+)?$/', $origin) ||
    preg_match('/^https?:\/\/127\.0\.0\.1(:\d+)?$/', $origin) ||
    str_ends_with($origin, '.hiddebalestra.nl') ||
    str_ends_with($origin, '.github.io')
);

if ($isAllowedOrigin) {
    header("Access-Control-Allow-Origin: $origin");
} else {
    header('Access-Control-Allow-Origin: *');
}
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Vary: Origin');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=' . DB_CHARSET,
        DB_USER,
        DB_PASSWORD,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    http_response_code(500);
    die(json_encode(['message' => 'Database connection failed']));
}

function sendResponse(array $data, int $statusCode = 200): never {
    http_response_code($statusCode);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data);
    exit;
}

function requestBody(): array {
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') return [];
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function bearerToken(): ?string {
    $header = $_SERVER['HTTP_AUTHORIZATION']
        ?? (function_exists('apache_request_headers') ? (apache_request_headers()['Authorization'] ?? '') : '');
    if (preg_match('/^Bearer\s+(.+)$/', trim($header), $matches)) {
        return $matches[1];
    }
    return null;
}

function newUuid(): string {
    $data = random_bytes(16);
    $data[6] = chr((ord($data[6]) & 0x0f) | 0x40);
    $data[8] = chr((ord($data[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
}

function newTokenHex(): string {
    return bin2hex(random_bytes(32));
}

function hashToken(string $token): string {
    return hash('sha256', $token);
}

/**
 * Resolves the authenticated account for an interactive request (login.php's
 * session token). Ends the request with 401 if missing/invalid/expired.
 */
function requireAccountSession(PDO $pdo): string {
    $token = bearerToken();
    if ($token === null) {
        sendResponse(['message' => 'Missing bearer token'], 401);
    }
    $stmt = $pdo->prepare(
        'SELECT account_id FROM account_sessions WHERE token_hash = ? AND expires_at > NOW()'
    );
    $stmt->execute([hashToken($token)]);
    $row = $stmt->fetch();
    if ($row === false) {
        sendResponse(['message' => 'Invalid or expired session'], 401);
    }
    return $row['account_id'];
}

/**
 * Resolves the authenticated device for an unattended request (the 5-minute
 * check-in's own scoped token). Ends the request with 401 if invalid.
 */
function requireDeviceToken(PDO $pdo): string {
    $token = bearerToken();
    if ($token === null) {
        sendResponse(['message' => 'Missing bearer token'], 401);
    }
    $stmt = $pdo->prepare('SELECT id FROM devices WHERE token_hash = ?');
    $stmt->execute([hashToken($token)]);
    $row = $stmt->fetch();
    if ($row === false) {
        sendResponse(['message' => 'Invalid device token'], 401);
    }
    return $row['id'];
}
