// Talks to the same PHP backend the Android app uses. Only ever sends the
// account code once, over HTTPS, to log in — everything after that uses the
// short-lived session token returned by login().

const DEFAULT_API_BASE = 'https://find.awake-music.co/api';

function apiBase() {
  return localStorage.getItem('fma_api_base') || DEFAULT_API_BASE;
}

async function request(method, path, { body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const response = await fetch(`${apiBase()}/${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json.message || `Request to ${path} failed (${response.status})`);
  }
  return json;
}

const Api = {
  login: (code, totp) => request('POST', 'login.php', { body: { code, totp } }),
  listDevices: (sessionToken) => request('GET', 'devices.php', { token: sessionToken }),
  listLocations: (sessionToken, deviceId, limit = 50) =>
    request('GET', `locations.php?deviceId=${encodeURIComponent(deviceId)}&limit=${limit}`, { token: sessionToken }),
  queueRing: (sessionToken, deviceId) => request('POST', 'ring.php', { token: sessionToken, body: { deviceId } }),
};
