// Mirrors app/lib/services/crypto_service.dart exactly: PBKDF2-HMAC-SHA256
// (210,000 iterations, 256-bit key) derives the location-encryption key from
// the account code + the account's public salt, then AES-256-GCM
// encrypts/decrypts a single base64 blob of (nonce || ciphertext || tag).
// Uses only the browser's native SubtleCrypto — no WASM/CDN crypto library,
// so there is nothing here to audit beyond this one small file.

const PBKDF2_ITERATIONS = 210000;
const NONCE_LENGTH = 12;

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

/** Derives the AES-256-GCM location-encryption key from code + salt. */
async function deriveKey(code, saltBase64) {
  const normalizedCode = code.trim().toLowerCase();
  const salt = base64ToBytes(saltBase64);
  const baseKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(normalizedCode),
    'PBKDF2',
    false,
    ['deriveKey'],
  );
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

/** Decrypts a base64(nonce || ciphertext || tag) blob back to plaintext JSON. */
async function decryptBlob(blobBase64, key) {
  const bytes = base64ToBytes(blobBase64);
  const nonce = bytes.slice(0, NONCE_LENGTH);
  const ciphertext = bytes.slice(NONCE_LENGTH);
  const plainBytes = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, ciphertext);
  return new TextDecoder().decode(plainBytes);
}

/** Encrypts plaintext JSON into a base64(nonce || ciphertext || tag) blob. */
async function encryptBlob(plaintext, key) {
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LENGTH));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, new TextEncoder().encode(plaintext)),
  );
  const combined = new Uint8Array(nonce.length + ciphertext.length);
  combined.set(nonce, 0);
  combined.set(ciphertext, nonce.length);
  return bytesToBase64(combined);
}
