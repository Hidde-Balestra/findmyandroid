<?php
/**
 * Hand-rolled tests for Totp (backend/api/totp.php) -- no PHPUnit/composer,
 * matching this backend's plain-PHP-file, no-vendor-dir convention. Run with
 * `php backend/tests/totp_test.php`; exits non-zero on any failure so it can
 * gate CI the same way `php -l` does.
 *
 * Only pure logic is covered here (no DB involved) -- Totp is the one piece
 * of backend/api that's fully self-contained and safe to exercise outside a
 * real deployment.
 */

declare(strict_types=1);

require __DIR__ . '/../api/totp.php';

$failures = 0;

function check(string $description, bool $condition): void {
    global $failures;
    if ($condition) {
        echo "  ok - $description\n";
    } else {
        echo "  FAIL - $description\n";
        $failures++;
    }
}

/** Reimplements Totp's private generateCode() so tests can cross-check
 * verify() against an independently computed code, without needing
 * reflection or a real authenticator app. */
function referenceCode(string $secret, int $counter): string {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $data = strtoupper(rtrim($secret, '='));
    $bits = '';
    foreach (str_split($data) as $char) {
        $index = strpos($alphabet, $char);
        if ($index === false) continue;
        $bits .= str_pad(decbin($index), 5, '0', STR_PAD_LEFT);
    }
    $key = '';
    foreach (str_split($bits, 8) as $chunk) {
        if (strlen($chunk) < 8) continue;
        $key .= chr(bindec($chunk));
    }

    $counterBytes = pack('N*', 0, $counter);
    $hash = hash_hmac('sha1', $counterBytes, $key, true);
    $offset = ord($hash[19]) & 0x0f;
    $truncated =
        ((ord($hash[$offset]) & 0x7f) << 24) |
        (ord($hash[$offset + 1]) << 16) |
        (ord($hash[$offset + 2]) << 8) |
        ord($hash[$offset + 3]);
    return str_pad((string)($truncated % 1000000), 6, '0', STR_PAD_LEFT);
}

echo "Totp::generateSecret\n";
$secret = Totp::generateSecret();
check('returns a non-empty base32 string', $secret !== '' && preg_match('/^[A-Z2-7]+$/', $secret) === 1);
check('two calls produce different secrets', Totp::generateSecret() !== Totp::generateSecret());

echo "Totp::provisioningUri\n";
$uri = Totp::provisioningUri($secret, 'someone@example.com', 'FindMyAndroid');
check('starts with otpauth://totp/', str_starts_with($uri, 'otpauth://totp/'));
check('includes the secret', str_contains($uri, "secret=$secret"));
check('includes the issuer', str_contains($uri, 'issuer=FindMyAndroid'));

echo "Totp::verify\n";
$counter = intdiv(time(), 30);
$currentCode = referenceCode($secret, $counter);
check('accepts an independently computed current-step code', Totp::verify($secret, $currentCode));

$adjacentCode = referenceCode($secret, $counter + 1);
check('accepts a code from the immediately adjacent step (default window)', Totp::verify($secret, $adjacentCode));

$farCode = referenceCode($secret, $counter + 5);
check('rejects a code far outside the window', !Totp::verify($secret, $farCode));

check('rejects a wrong 6-digit code', !Totp::verify($secret, '000000') || $currentCode === '000000');
check('rejects a malformed (non-6-digit) code', !Totp::verify($secret, '12345'));
check('rejects an empty code', !Totp::verify($secret, ''));

$otherSecret = Totp::generateSecret();
check(
    'a code valid for one secret is not valid for another',
    !Totp::verify($otherSecret, $currentCode) || referenceCode($otherSecret, $counter) === $currentCode,
);

if ($failures > 0) {
    echo "\n$failures check(s) failed.\n";
    exit(1);
}

echo "\nAll checks passed.\n";
