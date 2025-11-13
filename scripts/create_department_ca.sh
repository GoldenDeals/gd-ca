#!/usr/bin/env bash
set -euo pipefail
umask 077

DEPT="${1:-}"
if [[ -z "$DEPT" ]]; then
  echo "Usage: $0 <department-name>"; exit 1
fi

ROOT_CONF="configs/openssl-root.cnf"
DEPT_DIR="ca/departments/$DEPT"
TEMPLATE="configs/openssl-dept-template.cnf"
DEPT_CONF="$DEPT_DIR/openssl-$DEPT.cnf"

mkdir -p "$DEPT_DIR"/{certs,crl,newcerts,private,csr}
: > "$DEPT_DIR/index.txt"
echo 1000 > "$DEPT_DIR/serial"
echo 1000 > "$DEPT_DIR/crlnumber"

# Render dept config from template
sed "s/@DEPT@/$DEPT/g" "$TEMPLATE" > "$DEPT_CONF"

if [[ ! -f "$DEPT_DIR/private/ca.key.pem" ]]; then
  echo "[*] Generating $DEPT Issuing CA key (RSA-4096)…"
  openssl genrsa -out "$DEPT_DIR/private/ca.key.pem" 4096
  chmod 600 "$DEPT_DIR/private/ca.key.pem"
fi

echo "[*] Creating $DEPT CA CSR…"
openssl req -config "$DEPT_CONF" \
  -key "$DEPT_DIR/private/ca.key.pem" \
  -new -sha256 \
  -out "$DEPT_DIR/csr/ca.csr.pem"

echo "[*] Signing $DEPT CA with Root…"
openssl ca -config "$ROOT_CONF" -batch \
  -extensions v3_intermediate_ca \
  -days 3650 -notext -md sha256 \
  -in "$DEPT_DIR/csr/ca.csr.pem" \
  -out "$DEPT_DIR/ca.cert.pem"

chmod 644 "$DEPT_DIR/ca.cert.pem"

# Build chain (dept first, then root)
cat "$DEPT_DIR/ca.cert.pem" "ca/root/root.cert.pem" > "$DEPT_DIR/chain.cert.pem"

echo "[*] Generating initial $DEPT CRL…"
openssl ca -config "$DEPT_CONF" -gencrl -out "$DEPT_DIR/crl/$DEPT.crl.pem"

echo "[*] Syncing to ca-server…"
if [[ -f "scripts/sync_ca_server.sh" ]]; then
  ./scripts/sync_ca_server.sh >/dev/null 2>&1 || true
fi

echo "[✓] Department CA '$DEPT' ready at $DEPT_DIR"
echo "    Config: $DEPT_CONF"

