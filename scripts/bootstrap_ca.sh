#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="ca/root"
CONF="configs/openssl-root.cnf"

mkdir -p "$ROOT_DIR"/{certs,crl,newcerts,private,csr}
: > "$ROOT_DIR/index.txt"
echo 1000 > "$ROOT_DIR/serial"
echo 1000 > "$ROOT_DIR/crlnumber"

if [[ ! -f "$ROOT_DIR/private/root.key.pem" ]]; then
  echo "[*] Generating Root CA key (RSA-4096)…"
  openssl genrsa -out "$ROOT_DIR/private/root.key.pem" 4096
  chmod 600 "$ROOT_DIR/private/root.key.pem"
fi

if [[ ! -f "$ROOT_DIR/root.cert.pem" ]]; then
  echo "[*] Self-signing Root CA certificate…"
  openssl req -config "$CONF" \
    -key "$ROOT_DIR/private/root.key.pem" \
    -new -x509 -days 7300 -sha256 \
    -out "$ROOT_DIR/root.cert.pem"
  chmod 644 "$ROOT_DIR/root.cert.pem"
fi

echo "[*] Generating initial Root CRL…"
openssl ca -config "$CONF" -gencrl -out "$ROOT_DIR/crl/root.crl.pem"

echo "[*] Syncing to ca-server…"
if [[ -f "scripts/sync_ca_server.sh" ]]; then
  ./scripts/sync_ca_server.sh >/dev/null 2>&1 || true
fi

echo "[✓] Root CA ready at $ROOT_DIR"

