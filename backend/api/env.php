<?php
/**
 * Tiny dependency-free ".env" loader (no composer/vendor dir, matching the
 * rest of this backend). Most shared hosting doesn't give you access to set
 * real server/php-fpm environment variables, so this reads a plain
 * `KEY=value` file — `.env` next to this one, never committed (see
 * .gitignore) — and exposes it the same way real env vars would via
 * getenv(). If a variable is already set as a real environment variable,
 * that takes precedence and the .env file is not overridden.
 */

declare(strict_types=1);

$envFile = __DIR__ . '/.env';
if (is_readable($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $key = trim($key);
        $value = trim($value);
        if ($key === '' || getenv($key) !== false) {
            continue; // don't override a real environment variable
        }
        putenv("$key=$value");
        $_ENV[$key] = $value;
    }
}
