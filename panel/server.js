// XReality panel -- serves connection details, QR codes, and client configs.
const express = require('express');
const path = require('path');
const fs = require('fs/promises');
const QRCode = require('qrcode');

const app = express();
const PORT = process.env.PANEL_PORT || 3000;
const PASSWORD = process.env.PANEL_PASSWORD || '';
const CONFIG_DIR = process.env.CONFIG_DIR || '/data';
const SERVER_IP = process.env.SERVER_IP || '';

if (PASSWORD) {
  app.use((req, res, next) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Basic ')) {
      res.setHeader('WWW-Authenticate', 'Basic realm="XReality"');
      return res.status(401).json({ error: 'Authentication required' });
    }
    const decoded = Buffer.from(auth.slice(6), 'base64').toString();
    const sep = decoded.indexOf(':');
    const user = decoded.slice(0, sep);
    const pass = decoded.slice(sep + 1);
    if (user === 'admin' && pass === PASSWORD) {
      return next();
    }
    res.setHeader('WWW-Authenticate', 'Basic realm="XReality"');
    return res.status(401).json({ error: 'Invalid credentials' });
  });
}

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

async function readConfig(name) {
  try {
    return (await fs.readFile(path.join(CONFIG_DIR, name), 'utf-8')).trim();
  } catch {
    return null;
  }
}

let ipCache = null;
let ipCacheTime = 0;
const IP_CACHE_TTL = 300_000;

async function getExternalIP() {
  if (SERVER_IP) return SERVER_IP;
  if (ipCache && Date.now() - ipCacheTime < IP_CACHE_TTL) return ipCache;
  for (const url of ['https://ifconfig.me/ip', 'https://icanhazip.com', 'https://api.ipify.org']) {
    try {
      const res = await fetch(url, {
        signal: AbortSignal.timeout(5000),
        headers: { 'Accept': 'text/plain', 'User-Agent': 'curl/8.0' },
      });
      ipCache = (await res.text()).trim();
      ipCacheTime = Date.now();
      return ipCache;
    } catch {}
  }
  return 'UNKNOWN';
}

function buildShareLink(uuid, ip, port, publicKey, sni, shortId) {
  return `vless://${uuid}@${ip}:${port}?security=reality&encryption=none&pbk=${publicKey}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${sni}&sid=${shortId}#XReality`;
}

app.get('/api/status', async (_req, res) => {
  const uuid = await readConfig('uuid');
  const enablePq = await readConfig('enable_pq');
  const sni = await readConfig('sni');
  const shortId = await readConfig('short_id');
  res.json({
    initialized: !!uuid,
    pqEnabled: enablePq === 'true',
    sni: sni || 'unknown',
    shortId: shortId || 'unknown',
    version: '26.2.6',
  });
});

app.get('/api/connection', async (_req, res) => {
  const [uuid, publicKey, sni, shortId, enablePq, mldsa65Verify, vlessEnc, ip, port] = await Promise.all([
    readConfig('uuid'),
    readConfig('public_key'),
    readConfig('sni'),
    readConfig('short_id'),
    readConfig('enable_pq'),
    readConfig('mldsa65_verify'),
    readConfig('vlessenc_encryption'),
    getExternalIP(),
    readConfig('port'),
  ]);
  if (!uuid) {
    return res.status(503).json({ error: 'Proxy not initialized. Start the proxy container first.' });
  }
  const extPort = parseInt(port, 10) || 443;
  const data = {
    ip, port: extPort, uuid, publicKey,
    sni: sni || 'unknown',
    shortId: shortId || 'unknown',
    flow: 'xtls-rprx-vision',
    network: 'tcp',
    security: 'reality',
    fingerprint: 'chrome',
  };
  if (enablePq === 'true') {
    data.pq = { mldsa65Verify: mldsa65Verify || '', vlessEncryption: vlessEnc || '' };
  }
  res.json(data);
});

app.get('/api/link', async (_req, res) => {
  const [uuid, publicKey, sni, shortId, ip, port] = await Promise.all([
    readConfig('uuid'), readConfig('public_key'),
    readConfig('sni'), readConfig('short_id'), getExternalIP(), readConfig('port'),
  ]);
  if (!uuid) return res.status(503).json({ error: 'Not initialized' });
  const extPort = parseInt(port, 10) || 443;
  res.json({ link: buildShareLink(uuid, ip, extPort, publicKey, sni, shortId) });
});

app.get('/api/qr', async (_req, res) => {
  const [uuid, publicKey, sni, shortId, ip, port] = await Promise.all([
    readConfig('uuid'), readConfig('public_key'),
    readConfig('sni'), readConfig('short_id'), getExternalIP(), readConfig('port'),
  ]);
  if (!uuid) return res.status(503).json({ error: 'Not initialized' });
  const extPort = parseInt(port, 10) || 443;
  const link = buildShareLink(uuid, ip, extPort, publicKey, sni, shortId);
  try {
    const qr = await QRCode.toDataURL(link, { width: 320, margin: 2, color: { dark: '#e2e8f0', light: '#00000000' } });
    res.json({ qr, link });
  } catch {
    res.status(422).json({ error: 'Link too long for QR code', link });
  }
});

app.get('/api/config/download', async (_req, res) => {
  const [uuid, publicKey, sni, shortId, enablePq, mldsa65Verify, vlessEnc, ip, port] = await Promise.all([
    readConfig('uuid'), readConfig('public_key'),
    readConfig('sni'), readConfig('short_id'), readConfig('enable_pq'),
    readConfig('mldsa65_verify'), readConfig('vlessenc_encryption'), getExternalIP(), readConfig('port'),
  ]);
  if (!uuid) return res.status(503).json({ error: 'Not initialized' });

  const extPort = parseInt(port, 10) || 443;

  const encryption = enablePq === 'true' ? (vlessEnc || 'none') : 'none';
  const realitySettings = {
    serverName: sni, fingerprint: 'chrome',
    password: publicKey, shortId, spiderX: '/',
  };
  if (enablePq === 'true' && mldsa65Verify) {
    realitySettings.mldsa65Verify = mldsa65Verify;
  }

  const config = {
    outbounds: [{
      protocol: 'vless',
      settings: {
        vnext: [{ address: ip, port: extPort, users: [{ id: uuid, encryption, flow: 'xtls-rprx-vision' }] }],
      },
      streamSettings: { network: 'raw', security: 'reality', realitySettings },
    }],
  };

  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', 'attachment; filename="xreality-client.json"');
  res.json(config);
});

app.post('/api/regenerate', async (_req, res) => {
  try {
    await fs.unlink(path.join(CONFIG_DIR, '.lockfile'));
    ipCache = null;
    res.json({ success: true, message: 'Lockfile removed. Restart the proxy container to generate new keys.' });
  } catch (err) {
    if (err.code === 'ENOENT') {
      return res.json({ success: true, message: 'Already unlocked. Restart the proxy container.' });
    }
    res.status(500).json({ error: 'Failed to remove lockfile', details: err.message });
  }
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`XReality Panel running on http://0.0.0.0:${PORT}`);
  if (PASSWORD) {
    console.log('Authentication: enabled (user: admin)');
  } else {
    console.log('WARNING: No PANEL_PASSWORD set -- panel is unprotected');
  }
});
