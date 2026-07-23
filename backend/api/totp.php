<?php
/**
 * Minimal RFC 6238 TOTP (30s step, 6 digits, SHA-1 — the parameters every
 * mainstream authenticator app assumes) and RFC 4648 base32, hand-rolled so
 * this backend has no composer/vendor dependency, matching the rest of this
 * codebase's plain-PHP-file style.
 */

declare(strict_types=1);

final class Totp {
    private const STEP_SECONDS = 30;
    private const DIGITS = 6;
    private const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    public static function generateSecret(int $bytes = 20): string {
        return self::base32Encode(random_bytes($bytes));
    }

    public static function provisioningUri(string $secret, string $accountLabel, string $issuer): string {
        $label = rawurlencode($issuer) . ':' . rawurlencode($accountLabel);
        $query = http_build_query([
            'secret' => $secret,
            'issuer' => $issuer,
            'algorithm' => 'SHA1',
            'digits' => self::DIGITS,
            'period' => self::STEP_SECONDS,
        ]);
        return "otpauth://totp/$label?$query";
    }

    /** Accepts a code from the current or the immediately adjacent 30s step. */
    public static function verify(string $secret, string $code, int $window = 1): bool {
        $code = trim($code);
        if (!preg_match('/^\d{6}$/', $code)) {
            return false;
        }
        $timestamp = time();
        for ($offset = -$window; $offset <= $window; $offset++) {
            $counter = intdiv($timestamp, self::STEP_SECONDS) + $offset;
            if (hash_equals(self::generateCode($secret, $counter), $code)) {
                return true;
            }
        }
        return false;
    }

    private static function generateCode(string $secret, int $counter): string {
        $key = self::base32Decode($secret);
        $counterBytes = pack('N*', 0, $counter); // 8-byte big-endian counter
        $hash = hash_hmac('sha1', $counterBytes, $key, true);
        $offset = ord($hash[19]) & 0x0f;
        $truncated =
            ((ord($hash[$offset]) & 0x7f) << 24) |
            (ord($hash[$offset + 1]) << 16) |
            (ord($hash[$offset + 2]) << 8) |
            ord($hash[$offset + 3]);
        return str_pad((string)($truncated % (10 ** self::DIGITS)), self::DIGITS, '0', STR_PAD_LEFT);
    }

    private static function base32Encode(string $data): string {
        $bits = '';
        foreach (str_split($data) as $byte) {
            $bits .= str_pad(decbin(ord($byte)), 8, '0', STR_PAD_LEFT);
        }
        $output = '';
        foreach (str_split($bits, 5) as $chunk) {
            $chunk = str_pad($chunk, 5, '0', STR_PAD_RIGHT);
            $output .= self::BASE32_ALPHABET[bindec($chunk)];
        }
        return $output;
    }

    private static function base32Decode(string $data): string {
        $data = strtoupper(rtrim($data, '='));
        $bits = '';
        foreach (str_split($data) as $char) {
            $index = strpos(self::BASE32_ALPHABET, $char);
            if ($index === false) continue;
            $bits .= str_pad(decbin($index), 5, '0', STR_PAD_LEFT);
        }
        $bytes = '';
        foreach (str_split($bits, 8) as $chunk) {
            if (strlen($chunk) < 8) continue;
            $bytes .= chr(bindec($chunk));
        }
        return $bytes;
    }
}
