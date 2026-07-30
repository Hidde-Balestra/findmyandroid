-- Find My Android — database schema.
--
-- Deliberately contains no email, phone number, username, or any other
-- personally-identifying field anywhere. The only identity is a single
-- high-entropy account code (never stored in plaintext — only its
-- Argon2id hash and an HMAC lookup value) plus a TOTP second factor
-- (stored encrypted at rest). Location payloads are opaque ciphertext:
-- this server never has the key to read them.

CREATE TABLE IF NOT EXISTS accounts (
    id                     CHAR(36)      NOT NULL PRIMARY KEY,
    code_lookup            CHAR(64)      NOT NULL, -- HMAC-SHA256(code, pepper), indexed lookup only
    code_hash              VARCHAR(255)  NOT NULL, -- password_hash($code, PASSWORD_ARGON2ID)
    code_salt              VARCHAR(32)   NOT NULL, -- base64, public: client-side Argon2id salt for the location-encryption key
    totp_secret_ciphertext VARBINARY(255) NOT NULL, -- libsodium secretbox(secret, nonce, server key)
    totp_secret_nonce      VARBINARY(32)  NOT NULL,
    created_at             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_accounts_code_lookup (code_lookup)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS account_sessions (
    id          CHAR(36)     NOT NULL PRIMARY KEY,
    account_id  CHAR(36)     NOT NULL,
    token_hash  CHAR(64)     NOT NULL, -- SHA-256 of the bearer token; the token itself is never stored
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  DATETIME     NOT NULL,
    UNIQUE KEY uq_sessions_token_hash (token_hash),
    KEY idx_sessions_account (account_id),
    CONSTRAINT fk_sessions_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS devices (
    id            CHAR(36)     NOT NULL PRIMARY KEY,
    account_id    CHAR(36)     NOT NULL,
    label         VARCHAR(100) NOT NULL,
    token_hash    CHAR(64)     NOT NULL, -- SHA-256 of this device's scoped API token
    last_seen_at  DATETIME     NULL,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_devices_token_hash (token_hash),
    KEY idx_devices_account (account_id),
    CONSTRAINT fk_devices_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS locations (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    device_id    CHAR(36)        NOT NULL,
    ciphertext   TEXT            NOT NULL, -- base64(nonce || AES-256-GCM ciphertext || tag); opaque to this server
    captured_at  DATETIME        NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_locations_device_time (device_id, captured_at),
    CONSTRAINT fk_locations_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ring_commands (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    device_id     CHAR(36)        NOT NULL,
    status        ENUM('pending', 'delivered') NOT NULL DEFAULT 'pending',
    created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivered_at  DATETIME        NULL,
    KEY idx_ring_device_status (device_id, status),
    CONSTRAINT fk_ring_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Security snapshots (front-camera photo + location) logged after too many
-- failed account-code/TOTP attempts on a device. A documented, opt-in
-- feature (threshold configurable in-app, default 1, 0 = off) — not a
-- covert capability. Same opaque-ciphertext model as locations: this
-- server never has the key to view a photo or decrypt a location.
CREATE TABLE IF NOT EXISTS security_events (
    id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    device_id            CHAR(36)        NOT NULL,
    photo_ciphertext     LONGTEXT        NULL, -- base64(nonce || AES-256-GCM ciphertext || tag) of base64(JPEG)
    location_ciphertext  TEXT            NULL, -- same encoding as locations.ciphertext
    captured_at          DATETIME        NOT NULL,
    created_at           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_security_events_device_time (device_id, captured_at),
    CONSTRAINT fk_security_events_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
