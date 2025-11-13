#!/usr/bin/env bash
set -euo pipefail

DEPT="${1:-}"
CERT_PATH="${2:-}"

if [[ -z "$DEPT" || -z "$CERT_PATH" ]]; then
  echo "Usage: $0 <dept> </path/to/cert.pem>"; exit 1
fi

DEPT_DIR="ca/departments/$DEPT"
CONF="$DEPT_DIR/openssl-$DEPT.cnf"
[[ -f "$CONF" ]] || { echo "Missing dept config: $CONF"; exit 1; }
[[ -f "$CERT_PATH" ]] || { echo "Certificate not found: $CERT_PATH"; exit 1; }

echo "[*] Revoking certificate…"
openssl ca -config "$CONF" -revoke "$CERT_PATH" -crl_reason keyCompromise

echo "[*] Regenerating CRL…"
openssl ca -config "$CONF" -gencrl -out "$DEPT_DIR/crl/$DEPT.crl.pem"

echo "[*] Syncing CRL to ca-server…"
if [[ -f "scripts/sync_ca_server.sh" ]]; then
  ./scripts/sync_ca_server.sh >/dev/null 2>&1 || true
fi

echo "[✓] Revoked. Updated CRL at $DEPT_DIR/crl/$DEPT.crl.pem"

