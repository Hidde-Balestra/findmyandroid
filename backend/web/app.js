// Web viewer: log in with the account code + current TOTP code, then view
// each paired device's decrypted location history and queue "play sound".
// All decryption happens here, in the browser, using the code the user
// still has to type in — the server only ever hands over ciphertext.

let session = null; // { sessionToken, salt, code }
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
  ringButton: document.getElementById('ring-button'),
  ringStatus: document.getElementById('ring-status'),
  logoutButton: document.getElementById('logout-button'),
};

els.loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  els.loginError.textContent = '';
  const code = document.getElementById('code-input').value.trim();
  const totp = document.getElementById('totp-input').value.trim();

  try {
    const result = await Api.login(code, totp);
    session = { sessionToken: result.sessionToken, salt: result.salt, code };
    els.loginView.classList.add('hidden');
    els.appView.classList.remove('hidden');
    await loadDevices();
  } catch (err) {
    els.loginError.textContent = err.message;
  }
});

els.logoutButton.addEventListener('click', () => {
  session = null;
  els.appView.classList.add('hidden');
  els.loginView.classList.remove('hidden');
  els.loginForm.reset();
});

async function loadDevices() {
  const { devices } = await Api.listDevices(session.sessionToken);
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
  els.deviceDetail.classList.remove('hidden');
  els.deviceTitle.textContent = device.label;
  els.lastSeen.textContent = 'Loading history…';
  els.ringStatus.textContent = '';
  els.ringButton.onclick = () => ringDevice(device.id);

  const key = await deriveKey(session.code, session.salt);
  const { locations } = await Api.listLocations(session.sessionToken, device.id);

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
    await Api.queueRing(session.sessionToken, deviceId);
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
