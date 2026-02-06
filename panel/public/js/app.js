let connectionData = null;

const $loading = document.getElementById('loading-state');
const $error = document.getElementById('error-state');
const $errorMsg = document.getElementById('error-message');
const $dashboard = document.getElementById('dashboard');
const $statusDot = document.querySelector('.status-dot');
const $statusText = document.querySelector('.status-text');
const $qrLoading = document.getElementById('qr-loading');
const $qrImage = document.getElementById('qr-image');
const $pqSection = document.getElementById('pq-section');
const $confirmOverlay = document.getElementById('confirm-overlay');
const $toastContainer = document.getElementById('toast-container');

function toast(message, type = 'success') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = message;
  $toastContainer.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(12px)';
    el.style.transition = 'all 0.2s';
    setTimeout(() => el.remove(), 200);
  }, 2500);
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  }
}

document.addEventListener('click', async (e) => {
  const btn = e.target.closest('.copy-btn');
  if (!btn) return;
  const targetId = btn.dataset.target;
  const el = document.getElementById(targetId);
  if (!el) return;
  const ok = await copyText(el.textContent);
  if (ok) {
    btn.classList.add('copied');
    toast('Copied to clipboard');
    setTimeout(() => btn.classList.remove('copied'), 1500);
  }
});

async function api(path, opts = {}) {
  const res = await fetch(`/api${path}`, opts);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

async function init() {
  try {
    const [status, conn] = await Promise.all([
      api('/status'),
      api('/connection'),
    ]);

    connectionData = conn;

    // Status
    $statusDot.classList.add('online');
    $statusText.textContent = `Online | ${status.sni}`;

    // Connection fields
    document.getElementById('val-server').textContent = `${conn.ip}:${conn.port}`;
    document.getElementById('val-uuid').textContent = conn.uuid;
    document.getElementById('val-pubkey').textContent = conn.publicKey;
    document.getElementById('val-sni').textContent = conn.sni;
    document.getElementById('val-sid').textContent = conn.shortId;

    // PQ section
    if (conn.pq) {
      $pqSection.classList.remove('hidden');
      document.getElementById('val-mldsa').textContent = conn.pq.mldsa65Verify || '-';
      document.getElementById('val-vlessenc').textContent = conn.pq.vlessEncryption || '-';
    }

    // QR code
    try {
      const qrData = await api('/qr');
      $qrLoading.classList.add('hidden');
      $qrImage.src = qrData.qr;
      $qrImage.classList.remove('hidden');
    } catch {
      $qrLoading.classList.add('hidden');
    }

    // Show dashboard
    $loading.classList.add('hidden');
    $error.classList.add('hidden');
    $dashboard.classList.remove('hidden');

  } catch (err) {
    $statusDot.classList.add('offline');
    $statusText.textContent = 'Offline';
    $loading.classList.add('hidden');
    $errorMsg.textContent = err.message || 'Could not connect to proxy.';
    $error.classList.remove('hidden');
  }
}

document.getElementById('btn-copy-link').addEventListener('click', async () => {
  try {
    const data = await api('/link');
    await copyText(data.link);
    toast('Share link copied');
  } catch (err) {
    toast(err.message, 'error');
  }
});

document.getElementById('btn-download').addEventListener('click', () => {
  window.location.href = '/api/config/download';
});

document.getElementById('btn-regenerate').addEventListener('click', () => {
  $confirmOverlay.classList.remove('hidden');
});

document.getElementById('confirm-cancel').addEventListener('click', () => {
  $confirmOverlay.classList.add('hidden');
});

document.getElementById('confirm-yes').addEventListener('click', async () => {
  $confirmOverlay.classList.add('hidden');
  try {
    const data = await api('/regenerate', { method: 'POST' });
    toast(data.message || 'Keys will regenerate on restart');
  } catch (err) {
    toast(err.message, 'error');
  }
});

$confirmOverlay.addEventListener('click', (e) => {
  if (e.target === $confirmOverlay) {
    $confirmOverlay.classList.add('hidden');
  }
});

init();
