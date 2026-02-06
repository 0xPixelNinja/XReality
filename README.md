# XReality

A self-hosted VLESS + Reality proxy server with a **web management panel**, post-quantum cryptography, and one-command deployment. Designed for PaaS platforms like Coolify, CapRover, or any Docker host.

## Features

- **Xray-core v26.2.6** with VLESS + Vision + Reality
- **Web panel** for managing connections, QR codes, and client configs
- **Post-quantum cryptography** -- ML-KEM-768 + ML-DSA-65 (enabled by default)
- **One-command deploy** -- `make up` or `docker compose up -d`
- **PaaS-ready** -- `.env`-driven config, health checks, Coolify/CapRover compatible
- **Hardened** -- non-root containers, read-only filesystems, resource limits
- **Multi-arch** -- `linux/amd64` + `linux/arm64`

## Quick Start

```bash
git clone <your-repo-url>
cd xreality
cp .env.example .env    # edit settings if needed
make up
```

Open `http://your-server:3000` to access the panel.

The proxy listens on port 443, the panel on port 3000. All keys are auto-generated on first run.

## Architecture

```
docker compose up
       |
       |- proxy  (Alpine + Xray-core)  -> port 443
       |    Generates keys on first boot
       |    Writes config to shared volume
       |
       |- panel  (Node.js + Express)   -> port 3000
            Reads keys from shared volume
            Serves web dashboard + API
       |
       [config-data volume]
         uuid, public_key, private_key
         mldsa65_seed, mldsa65_verify
         vlessenc_decryption, vlessenc_encryption
         sni, short_id, enable_pq
         config.json (generated at startup)
```

## Configuration

All settings are managed via `.env` file (copied from `.env.example`):

| Variable | Description | Default |
|----------|-------------|---------|
| `SNI` | Camouflage domain (must support TLSv1.3 + HTTP/2) | `www.samsung.com` |
| `SHORT_ID` | Hex string for Reality handshake (empty = random) | _(auto)_ |
| `ENABLE_PQ` | Post-quantum crypto (ML-KEM-768 + ML-DSA-65) | `true` |
| `ENABLE_STATS` | Xray stats API inside container | `false` |
| `PROXY_PORT` | Host port for the proxy | `443` |
| `PANEL_PORT` | Host port for the web panel | `3000` |
| `PANEL_PASSWORD` | Panel login password (user: `admin`). Empty = no auth | _(empty)_ |
| `SERVER_IP` | Override auto-detected IP (for NAT/PaaS/CDN) | _(auto)_ |

## Web Panel

The panel provides:

- **Connection details** -- server IP, UUID, public key, SNI, short ID
- **QR code** -- scan with v2rayNG, Hiddify, Streisand, or any VLESS client
- **Copy share link** -- `vless://` URI for one-click import
- **Download JSON** -- ready-to-import client outbound config
- **Post-quantum info** -- ML-DSA-65 verify key and VLESS encryption string
- **Regenerate keys** -- invalidate all clients and generate fresh credentials

The panel is protected with HTTP Basic Auth when `PANEL_PASSWORD` is set.

## CLI Access

All panel operations are also available via the proxy container's CLI:

```bash
docker exec xreality-proxy bash ./client-config.sh show
docker exec xreality-proxy bash ./client-config.sh link
docker exec xreality-proxy bash ./client-config.sh qr
docker exec xreality-proxy bash ./client-config.sh json
docker exec xreality-proxy bash ./client-config.sh regenerate
```

Or via Make targets: `make client-show`, `make client-qr`, etc.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make up` | Build and start everything |
| `make down` | Stop and remove containers |
| `make build` | Rebuild images without cache |
| `make restart` | Restart all services |
| `make logs` | Tail all container logs |
| `make logs-proxy` | Tail proxy logs only |
| `make logs-panel` | Tail panel logs only |
| `make client-show` | Print connection details (CLI) |
| `make client-link` | Print share link (CLI) |
| `make client-qr` | Show QR code in terminal (CLI) |
| `make client-json` | Output client JSON (CLI) |
| `make regenerate` | Regenerate keys and restart proxy |
| `make clean` | Remove containers, volumes, and images |

## PaaS Deployment

### Coolify

Coolify's Traefik proxy already occupies port 443. The VLESS Reality protocol is raw TLS (not HTTP), so it **cannot** be routed through Traefik. Use a different port for the proxy:

1. Create a new service from a **Docker Compose** source.
2. Point to your Git repository.
3. Set environment variables in the Coolify UI -- critically:
   - `PROXY_PORT=8443` (or any port not used by Traefik: 2053, 2083, 2087, etc.)
   - `SERVER_IP=<your-server-public-ip>`
   - `PANEL_PASSWORD=<something-strong>`
4. Let Coolify handle the panel service normally (assign a domain, it gets SSL via Traefik).
5. The proxy port (`8443`) must be directly exposed on the host firewall.
6. Deploy. Clients connect to `your-server:8443`.

### CapRover / Other PaaS

Same principle -- set `PROXY_PORT` to avoid conflicts with the platform's reverse proxy. The panel can sit behind the platform's proxy since it's standard HTTP.

### Important for PaaS

- Set `SERVER_IP` -- auto-detection may not work behind NAT/load balancers.
- Set `PANEL_PASSWORD` -- the panel will be publicly accessible.
- Set `PROXY_PORT` to a non-443 port if 443 is taken by the platform.

## Connecting Clients

### Mobile (Android / iOS)

1. Open the panel at `http://your-server:3000`
2. Scan the QR code with v2rayNG, Hiddify, Streisand, or FoXray
3. The connection is auto-configured

### Desktop

1. Click "Copy Share Link" in the panel and paste into your client
2. Or click "Download JSON" and import the config file

## Security

| Measure | Implementation |
|---------|---------------|
| Non-root execution | Proxy runs as `xray`, panel runs as `node` |
| Read-only filesystem | Both containers use `read_only: true` |
| Privilege escalation blocked | `no-new-privileges` on both containers |
| Resource limits | Proxy: 128MB / 1 CPU; Panel: 64MB / 0.5 CPU |
| Private IP blocking | Routing rule blocks `geoip:private` |
| QUIC sniffing | Prevents protocol bypass |
| Minimum client version | Rejects Xray clients older than v26.1.23 |
| Panel auth | HTTP Basic Auth via `PANEL_PASSWORD` |
| Health checks | TCP probe on proxy, HTTP probe on panel |

## Project Structure

```
.
├── docker-compose.yaml       # Two-service orchestration
├── .env.example              # All configurable settings
├── Makefile                  # Convenience targets
├── proxy/
│   ├── Dockerfile            # Alpine + xray binary from official GHCR image
│   ├── config.template.json  # Xray config (jq placeholders)
│   ├── entrypoint.sh         # Key generation + config build + exec xray
│   ├── client-config.sh      # CLI config tool (show/link/qr/json/regenerate)
│   └── .dockerignore
├── panel/
│   ├── Dockerfile            # Node 22 Alpine
│   ├── package.json
│   ├── server.js             # Express API + Basic Auth
│   ├── .dockerignore
│   └── public/
│       ├── index.html        # Dashboard SPA
│       ├── css/styles.css    # Dark theme
│       └── js/app.js         # Client-side logic
└── LICENSE
```

## Sources

| Resource | URL |
|----------|-----|
| Xray-core | https://github.com/XTLS/Xray-core |
| XTLS Documentation | https://xtls.github.io |

## License

See [LICENSE](LICENSE) for details.
