#!/bin/bash
# Generates keys on first run, builds xray config from template, and launches xray.
set -euo pipefail

CONFIG_DIR="config"
LOCKFILE="${CONFIG_DIR}/.lockfile"
TEMPLATE="${CONFIG_DIR}/config.template.json"
CONFIG="${CONFIG_DIR}/config.json"

if [[ -z "${SHORT_ID:-}" ]]; then
  SHORT_ID=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
  echo "Generated random Short ID: ${SHORT_ID}"
fi

# Written so the panel container can read runtime settings
echo "${SNI}" > "${CONFIG_DIR}/sni"
echo "${SHORT_ID}" > "${CONFIG_DIR}/short_id"
echo "${ENABLE_PQ:-true}" > "${CONFIG_DIR}/enable_pq"
echo "${PROXY_PORT:-443}" > "${CONFIG_DIR}/port"

if [[ ! -f "${LOCKFILE}" ]]; then
  echo "First run detected -- generating keys..."

  xray uuid > "${CONFIG_DIR}/uuid"
  echo "UUID: $(cat "${CONFIG_DIR}/uuid")"

  X25519_OUTPUT=$(xray x25519)
  echo "${X25519_OUTPUT}" | awk '/PrivateKey/{print $2}' > "${CONFIG_DIR}/private_key"
  echo "${X25519_OUTPUT}" | awk '/Password/{print $2}' > "${CONFIG_DIR}/public_key"
  echo "x25519 keypair generated"

  MLDSA_OUTPUT=$(xray mldsa65)
  echo "${MLDSA_OUTPUT}" | awk '/Seed/{print $2}' > "${CONFIG_DIR}/mldsa65_seed"
  echo "${MLDSA_OUTPUT}" | awk '/Verify/{print $2}' > "${CONFIG_DIR}/mldsa65_verify"
  echo "ML-DSA-65 keypair generated"

  VLESSENC_OUTPUT=$(xray vlessenc)
  echo "${VLESSENC_OUTPUT}" | awk '/"decryption"/{gsub(/"/, "", $2); print $2; exit}' > "${CONFIG_DIR}/vlessenc_decryption"
  echo "${VLESSENC_OUTPUT}" | awk '/"encryption"/{gsub(/"/, "", $2); print $2; exit}' > "${CONFIG_DIR}/vlessenc_encryption"
  echo "VLESS encryption pair generated"

  for f in uuid private_key public_key mldsa65_seed mldsa65_verify vlessenc_decryption vlessenc_encryption; do
    if [[ ! -s "${CONFIG_DIR}/${f}" ]]; then
      echo "FATAL: ${f} is empty after generation. Aborting." >&2
      exit 1
    fi
  done

  touch "${LOCKFILE}"
  echo "Lockfile created -- keys will persist across restarts"
fi

chmod -R g+r "${CONFIG_DIR}" 2>/dev/null || true
chmod g+w "${CONFIG_DIR}" 2>/dev/null || true

UUID=$(cat "${CONFIG_DIR}/uuid")
PRIVATE_KEY=$(cat "${CONFIG_DIR}/private_key")

DECRYPTION="none"
if [[ "${ENABLE_PQ:-true}" == "true" ]] && [[ -f "${CONFIG_DIR}/vlessenc_decryption" ]]; then
  DECRYPTION=$(cat "${CONFIG_DIR}/vlessenc_decryption")
  echo "Post-quantum VLESS encryption: enabled"
else
  echo "Post-quantum VLESS encryption: disabled"
fi

REALITY_SETTINGS_EXTRA="{}"
if [[ "${ENABLE_PQ:-true}" == "true" ]] && [[ -f "${CONFIG_DIR}/mldsa65_seed" ]]; then
  MLDSA65_SEED=$(cat "${CONFIG_DIR}/mldsa65_seed")
  REALITY_SETTINGS_EXTRA=$(jq -n --arg seed "${MLDSA65_SEED}" '{"mldsa65Seed": $seed}')
  echo "Post-quantum Reality ML-DSA-65: enabled"
fi

jq \
  --arg uuid "${UUID}" \
  --arg privateKey "${PRIVATE_KEY}" \
  --arg sni "${SNI}" \
  --arg shortId "${SHORT_ID}" \
  --arg decryption "${DECRYPTION}" \
  --argjson realityExtra "${REALITY_SETTINGS_EXTRA}" \
  '
    .inbounds[0].settings.clients[0].id = $uuid |
    .inbounds[0].settings.decryption = $decryption |
    .inbounds[0].streamSettings.realitySettings.privateKey = $privateKey |
    .inbounds[0].streamSettings.realitySettings.target = ($sni + ":443") |
    .inbounds[0].streamSettings.realitySettings.serverNames = [$sni] |
    .inbounds[0].streamSettings.realitySettings.shortIds = [$shortId] |
    .inbounds[0].streamSettings.realitySettings += $realityExtra
  ' "${TEMPLATE}" > "${CONFIG}"

if [[ "${ENABLE_STATS:-false}" == "true" ]]; then
  jq '
    .api = {"tag": "api", "services": ["StatsService"]} |
    .inbounds += [{
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "tag": "api_inbound",
      "settings": {"address": "127.0.0.1"}
    }] |
    .routing.rules = [{"type": "field", "inboundTag": ["api_inbound"], "outboundTag": "api"}] + .routing.rules
  ' "${CONFIG}" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "${CONFIG}"
  echo "Stats API: enabled on 127.0.0.1:10085"
fi

echo ""
echo "=== XReality Server ==="
echo "SNI:       ${SNI}"
echo "Short ID:  ${SHORT_ID}"
echo "PQ:        ${ENABLE_PQ:-true}"
echo "Stats:     ${ENABLE_STATS:-false}"
echo "==========================="
echo ""

exec xray run -config "${CONFIG}"
