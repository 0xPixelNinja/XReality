# XReality

VLESS + Reality proxy with a web panel, post-quantum cryptography, and Docker Compose deployment.

## Features

- **Xray-core v26.2.6** -- VLESS + Vision + Reality
- **Web panel** -- connection details, QR codes, share links, client config downloads
- **Post-quantum cryptography** -- ML-KEM-768 + ML-DSA-65 (on by default)
- **Hardened containers** -- non-root, read-only filesystems, resource limits, no privilege escalation
- **Auto key generation** -- UUID, x25519, ML-DSA-65, and VLESS encryption keys created on first boot

## Prerequisites

- A VPS running Linux (Ubuntu, Debian, etc.)
- Docker Engine 24+ and Docker Compose v2
- Ports `443` and `3000` open in your firewall

Install Docker if you don't have it:

```bash
curl -fsSL https://get.docker.com | sh
```

## Install

```bash
git clone https://github.com/your-user/xtls-reality-docker.git
cd xtls-reality-docker
cp .env.example .env
```

Edit `.env` to set at minimum:

```bash
PANEL_PASSWORD=your-strong-password
```

Then start:

```bash
docker compose up -d --build
```

That's it. The proxy runs on `:443` and the panel on `:3000`. All keys are generated automatically on first boot.

Open `http://<your-server-ip>:3000` (user: `admin`, password: your `PANEL_PASSWORD`).

## Configuration

All settings live in `.env`:

| Variable | Description | Default |
|----------|-------------|---------|
| `SNI` | Camouflage domain (must support TLSv1.3 + HTTP/2) | `www.samsung.com` |
| `SHORT_ID` | Hex string for Reality handshake (empty = random) | _(auto)_ |
| `ENABLE_PQ` | Post-quantum crypto (ML-KEM-768 + ML-DSA-65) | `true` |
| `ENABLE_STATS` | Xray stats API inside container | `false` |
| `PROXY_PORT` | Host port for the proxy | `443` |
| `PANEL_PORT` | Host port for the web panel | `3000` |
| `PANEL_PASSWORD` | Panel login password (user: `admin`). Empty = no auth | _(empty)_ |
| `SERVER_IP` | Override auto-detected public IP (for NAT/CDN) | _(auto)_ |

After changing `.env`, apply with:

```bash
docker compose up -d --build
```

### Common scenarios

**Port 443 is already in use** (e.g. by nginx):

```env
PROXY_PORT=8443
```

Clients will connect to `your-server:8443` instead.

**VPS is behind NAT** or IP detection returns the wrong address:

```env
SERVER_IP=203.0.113.10
```

## Usage

### Web Panel

Open `http://<your-server-ip>:3000` to:

- View connection details (IP, UUID, public key, SNI, short ID)
- Scan a QR code with v2rayNG, Hiddify, Streisand, or FoXray
- Copy a `vless://` share link
- Download a ready-to-import client JSON config
- View post-quantum keys (ML-DSA-65 verify, VLESS encryption)
- Regenerate all keys (invalidates existing clients)

### CLI

Same operations available from the terminal:

```bash
docker exec xreality-proxy bash ./client-config.sh show         # print connection details
docker exec xreality-proxy bash ./client-config.sh link         # vless:// share URI
docker exec xreality-proxy bash ./client-config.sh qr           # QR code in terminal
docker exec xreality-proxy bash ./client-config.sh json         # full client JSON config
docker exec xreality-proxy bash ./client-config.sh regenerate   # regenerate keys
```

### Connecting Clients

**Mobile** -- open the panel, scan the QR code with your VLESS client app.

**Desktop** -- click "Copy Share Link" and paste into your client, or click "Download JSON" and import the file.

## Common Commands

```bash
docker compose up -d --build    # start / rebuild
docker compose down             # stop
docker compose restart          # restart
docker compose logs -f          # tail logs
docker compose logs -f proxy    # proxy logs only
docker compose logs -f panel    # panel logs only
docker compose down -v --rmi local  # remove everything including volumes
```

A `Makefile` is included as a shorthand -- run `make up`, `make down`, `make logs`, `make client-qr`, etc.

## Architecture

```
docker compose up -d
        |
        |- proxy  (Alpine + Xray-core)  -> :443
        |    Generates keys on first boot
        |    Writes config to shared volume
        |
        |- panel  (Node.js + Express)   -> :3000
        |    Reads keys from shared volume
        |    Serves web dashboard + API
        |
        [config-data volume]
          uuid, public_key, private_key
          mldsa65_seed, mldsa65_verify
          vlessenc_decryption, vlessenc_encryption
          sni, short_id, enable_pq
          config.json
```

## Security

| Measure | Detail |
|---------|--------|
| Non-root | Proxy runs as `xray:1000`, panel runs as `node` |
| Read-only filesystem | Both containers use `read_only: true` |
| No privilege escalation | `no-new-privileges` security option |
| Resource limits | Proxy: 128 MB / 1 CPU -- Panel: 64 MB / 0.5 CPU |
| Private IP blocking | Routing rule blocks `geoip:private` |
| Sniffing | HTTP, TLS, QUIC sniffing enabled |
| Min client version | Rejects Xray clients older than v26.1.23 |
| Panel auth | HTTP Basic Auth when `PANEL_PASSWORD` is set |
| Health checks | TCP probe on proxy, HTTP probe on panel |

## Project Structure

```
.
├── docker-compose.yaml        # service orchestration
├── Dockerfile                 # multi-stage build (proxy + panel)
├── .env.example               # configuration template
├── Makefile                   # shorthand commands
├── proxy/
│   ├── config.template.json   # xray config template (jq-substituted)
│   ├── entrypoint.sh          # key generation + config build + xray exec
│   └── client-config.sh       # CLI tool (show/link/qr/json/regenerate)
└── panel/
    ├── package.json
    ├── server.js              # Express API + Basic Auth
    └── public/
        ├── index.html
        ├── css/styles.css
        └── js/app.js
```

## License

See [LICENSE](LICENSE) for details.
