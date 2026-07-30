// Web viewer: log in with the account code + current TOTP code, then view
// each paired device's decrypted location history and queue "play sound".
// All decryption happens here, in the browser, using the code the user
// still has to type in — the server only ever hands over ciphertext.

// Kept in the browser for convenience, not just in memory: a page refresh
// (or closing/reopening the tab) doesn't force logging in again for up to
// SESSION_LIFETIME_MS. This does mean the account code sits in localStorage
// for that window — anyone with access to this browser profile during that
// time can derive the decryption key without needing the TOTP device. The
// server-side session token itself also expires after the same window (see
// ACCOUNT_SESSION_LIFETIME_SECONDS in backend/api/config.php), so a stored
// session can't outlive its window even if localStorage is copied elsewhere.
const SESSION_STORAGE_KEY = 'fma_session';
const SESSION_LIFETIME_MS = 2 * 60 * 60 * 1000; // 2 hours

let session = null; // { sessionToken, salt, code, expiresAt }
let currentDevice = null;
let map = null;
let marker = null;
let polyline = null;

const els = {
  loginView: document.getElementById('login-view'),
  appView: document.getElementById('app-view'),
  loginForm: document.getElementById('login-form'),
  loginError: document.getElementById('login-error'),
  deviceList: document.getElementById('device-list'),
  deviceDetail: document.getElementById('device-detail'),
  deviceTitle: document.getElementById('device-title'),
  lastSeen: document.getElementById('last-seen'),
  refreshButton: document.getElementById('refresh-button'),
  ringButton: document.getElementById('ring-button'),
  ringStatus: document.getElementById('ring-status'),
  logoutButton: document.getElementById('logout-button'),
};

function saveSession() {
  localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
}

function loadStoredSession() {
  const raw = localStorage.getItem(SESSION_STORAGE_KEY);
  if (!raw) return null;
  try {
    const stored = JSON.parse(raw);
    if (!stored.expiresAt || stored.expiresAt <= Date.now()) {
      localStorage.removeItem(SESSION_STORAGE_KEY);
      return null;
    }
    return stored;
  } catch {
    localStorage.removeItem(SESSION_STORAGE_KEY);
    return null;
  }
}

function showApp() {
  els.loginView.classList.add('hidden');
  els.appView.classList.remove('hidden');
}

function showLogin() {
  session = null;
  currentDevice = null;
  localStorage.removeItem(SESSION_STORAGE_KEY);
  els.appView.classList.add('hidden');
  els.loginView.classList.remove('hidden');
  els.loginForm.reset();
}

/** Runs an API call; if the session turns out to be expired/invalid
 * mid-use, drops back to the login screen instead of showing a raw error. */
async function withSession(fn) {
  try {
    return await fn();
  } catch (err) {
    if (err.status === 401) {
      showLogin();
      els.loginError.textContent = 'Your session expired — log in again.';
    }
    throw err;
  }
}

els.loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  els.loginError.textContent = '';
  const code = document.getElementById('code-input').value.trim();
  const totp = document.getElementById('totp-input').value.trim();

  try {
    const result = await Api.login(code, totp);
    session = {
      sessionToken: result.sessionToken,
      salt: result.salt,
      code,
      expiresAt: Date.now() + SESSION_LIFETIME_MS,
    };
    saveSession();
    showApp();
    await loadDevices();
  } catch (err) {
    els.loginError.textContent = err.message;
  }
});

els.logoutButton.addEventListener('click', showLogin);

els.refreshButton.addEventListener('click', () => {
  if (currentDevice) showDevice(currentDevice);
});

// Resume a still-valid session on page load instead of asking to log in again.
(() => {
  const stored = loadStoredSession();
  if (stored) {
    session = stored;
    showApp();
    loadDevices();
  }
})();

async function loadDevices() {
  const { devices } = await withSession(() => Api.listDevices(session.sessionToken));
  els.deviceList.innerHTML = '';
  if (devices.length === 0) {
    els.deviceList.innerHTML = '<p>No devices paired to this account yet.</p>';
    return;
  }
  for (const device of devices) {
    const item = document.createElement('button');
    item.className = 'device-item';
    item.textContent = device.label;
    item.addEventListener('click', () => showDevice(device));
    els.deviceList.appendChild(item);
  }
  // Show the first device by default.
  showDevice(devices[0]);
}

async function showDevice(device) {
  currentDevice = device;
  els.deviceDetail.classList.remove('hidden');
  els.deviceTitle.textContent = device.label;
  els.lastSeen.textContent = 'Loading history…';
  els.ringStatus.textContent = '';
  els.ringButton.onclick = () => ringDevice(device.id);

  const key = await deriveKey(session.code, session.salt);
  const { locations } = await withSession(() => Api.listLocations(session.sessionToken, device.id));

  const points = [];
  for (const point of locations) {
    try {
      const plaintext = await decryptBlob(point.ciphertext, key);
      const sample = JSON.parse(plaintext);
      points.push({ lat: sample.lat, lng: sample.lng, capturedAt: sample.capturedAt });
    } catch {
      // Skip a point that fails to decrypt/authenticate rather than
      // aborting the whole history load.
    }
  }

  if (points.length === 0) {
    els.lastSeen.textContent = 'No location samples yet.';
    return;
  }

  const latest = points[points.length - 1];
  els.lastSeen.textContent = `Last seen: ${new Date(latest.capturedAt).toLocaleString()}`;
  renderMap(points);
}

async function ringDevice(deviceId) {
  els.ringStatus.textContent = 'Queuing…';
  try {
    await withSession(() => Api.queueRing(session.sessionToken, deviceId));
    els.ringStatus.textContent = 'Sound queued — plays next time this device checks in (within 5 min).';
  } catch (err) {
    els.ringStatus.textContent = `Failed: ${err.message}`;
  }
}

function renderMap(points) {
  const latLngs = points.map((p) => [p.lat, p.lng]);
  const latest = latLngs[latLngs.length - 1];

  if (!map) {
    map = L.map('map').setView(latest, 15);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19,
    }).addTo(map);
  } else {
    map.setView(latest, 15);
  }

  if (marker) map.removeLayer(marker);
  if (polyline) map.removeLayer(polyline);

  marker = L.marker(latest).addTo(map);
  polyline = L.polyline(latLngs, { color: '#3D5AFE' }).addTo(map);
}
