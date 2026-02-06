#!/bin/bash
set -euo pipefail

CONFIG_DIR="config"
CMD="${1:-help}"

get_ip() {
  curl -sf --max-time 5 ifconfig.me 2>/dev/null \
    || curl -sf --max-time 5 icanhazip.com 2>/dev/null \
    || echo "UNKNOWN"
}

check_secrets() {
  local missing=0
  for f in uuid public_key mldsa65_verify vlessenc_encryption; do
    if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
      echo "ERROR: ${CONFIG_DIR}/${f} not found. Has the server started at least once?" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -eq 1 ]]; then exit 1; fi
}

case "${CMD}" in
  show)
    check_secrets
    EXT_IP=$(get_ip)
    PORT="${PROXY_PORT:-443}"
    echo ""
    echo "=== Client Connection Details ==="
    echo "Server:       ${EXT_IP}:${PORT}"
    echo "UUID:         $(cat "${CONFIG_DIR}/uuid")"
    echo "Public Key:   $(cat "${CONFIG_DIR}/public_key")"
    echo "SNI:          ${SNI}"
    echo "Short ID:     ${SHORT_ID:-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
    echo "Flow:         xtls-rprx-vision"
    echo "Network:      tcp"
    echo "Security:     reality"
    echo "Fingerprint:  chrome"
    if [[ "${ENABLE_PQ:-true}" == "true" ]]; then
      echo ""
      echo "--- Post-Quantum ---"
      echo "ML-DSA-65 Verify: $(cat "${CONFIG_DIR}/mldsa65_verify")"
      echo "VLESS Encryption: $(cat "${CONFIG_DIR}/vlessenc_encryption")"
    fi
    echo "================================="
    echo ""
    ;;
  link)
    check_secrets
    EXT_IP=$(get_ip)
    PORT="${PROXY_PORT:-443}"
    UUID=$(cat "${CONFIG_DIR}/uuid")
    PUB_KEY=$(cat "${CONFIG_DIR}/public_key")
    SID="${SHORT_ID:-}"
    ENCRYPTION="none"
    MLDSA_PARAM=""
    if [[ "${ENABLE_PQ:-true}" == "true" ]] && [[ -f "${CONFIG_DIR}/vlessenc_encryption" ]]; then
      ENCRYPTION=$(cat "${CONFIG_DIR}/vlessenc_encryption")
    fi
    if [[ "${ENABLE_PQ:-true}" == "true" ]] && [[ -f "${CONFIG_DIR}/mldsa65_verify" ]]; then
      MLDSA_PARAM="&mldsa65Verify=$(cat "${CONFIG_DIR}/mldsa65_verify")"
    fi
    LINK="vless://${UUID}@${EXT_IP}:${PORT}?security=reality&encryption=${ENCRYPTION}&pbk=${PUB_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&sid=${SID}${MLDSA_PARAM}#XReality"
    echo "${LINK}"
    ;;
  qr)
    check_secrets
    LINK=$(bash "$0" link)
    echo ""
    echo "${LINK}"
    echo ""
    qrencode -t ansiutf8 <<< "${LINK}"
    ;;
  json)
    check_secrets
    EXT_IP=$(get_ip)
    PORT="${PROXY_PORT:-443}"
    UUID=$(cat "${CONFIG_DIR}/uuid")
    PUB_KEY=$(cat "${CONFIG_DIR}/public_key")
    SID="${SHORT_ID:-}"
    ENCRYPTION="none"
    MLDSA_VERIFY=""
    if [[ "${ENABLE_PQ:-true}" == "true" ]]; then
      ENCRYPTION=$(cat "${CONFIG_DIR}/vlessenc_encryption")
      MLDSA_VERIFY=$(cat "${CONFIG_DIR}/mldsa65_verify")
    fi
    jq -n \
      --arg ip "${EXT_IP}" \
      --argjson port "${PORT}" \
      --arg uuid "${UUID}" \
      --arg pubKey "${PUB_KEY}" \
      --arg sni "${SNI}" \
      --arg sid "${SID}" \
      --arg encryption "${ENCRYPTION}" \
      --arg mldsaVerify "${MLDSA_VERIFY}" \
      '{
        "outbounds": [{
          "protocol": "vless",
          "settings": {
            "vnext": [{
              "address": $ip,
              "port": $port,
              "users": [{
                "id": $uuid,
                "encryption": $encryption,
                "flow": "xtls-rprx-vision"
              }]
            }]
          },
          "streamSettings": {
            "network": "raw",
            "security": "reality",
            "realitySettings": {
              "serverName": $sni,
              "fingerprint": "chrome",
              "password": $pubKey,
              "shortId": $sid,
              "spiderX": "/"
            } + (if $mldsaVerify != "" then {"mldsa65Verify": $mldsaVerify} else {} end)
          }
        }]
      }'
    ;;
  regenerate)
    echo "Removing lockfile to force key regeneration on next start..."
    rm -f "${CONFIG_DIR}/.lockfile"
    echo "Sending SIGTERM to xray process..."
    kill -TERM 1 2>/dev/null || true
    echo ""
    echo "Container will restart and generate fresh keys."
    echo "Old client configs will stop working."
    ;;
  help|*)
    echo ""
    echo "Usage: client-config.sh <command>"
    echo ""
    echo "Commands:"
    echo "  show        Print connection details"
    echo "  link        Generate vless:// share URI"
    echo "  qr          Show QR code for mobile clients"
    echo "  json        Output full client JSON config"
    echo "  regenerate  Delete keys and restart (new keys on next boot)"
    echo ""
    ;;
esac
