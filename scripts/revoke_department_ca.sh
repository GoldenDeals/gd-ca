#!/usr/bin/env bash
set -euo pipefail

# Revoke a department CA and all its issued certificates
# Usage: ./scripts/revoke_department_ca.sh <department>

DEPT="${1:-}"
if [[ -z "$DEPT" ]]; then
  echo "Usage: $0 <department>"
  exit 1
fi

ROOT_CONF="configs/openssl-root.cnf"
ROOT_DIR="ca/root"
DEPT_DIR="ca/departments/$DEPT"
RECYCLE_DIR="ca/recycle-bin/$DEPT-$(date +%Y%m%d%H%M%S)"

if [[ ! -d "$DEPT_DIR" ]]; then
  echo "Department CA '$DEPT' not found in $DEPT_DIR"
  exit 1
fi

DEPT_CONF="$DEPT_DIR/openssl-$DEPT.cnf"
DEPT_CERT="$DEPT_DIR/ca.cert.pem"
DEPT_CHAIN="$DEPT_DIR/chain.cert.pem"
DEPT_KEY="$DEPT_DIR/private/ca.key.pem"
DEPT_INDEX="$DEPT_DIR/index.txt"
DEPT_CRL="$DEPT_DIR/crl/$DEPT.crl.pem"

echo "[*] Revoking Department CA '$DEPT'..."

# 1. Revoke all issued certificates for this department
if [[ -f "$DEPT_INDEX" ]]; then
  while read -r LINE; do
    STATUS=$(echo "$LINE" | cut -c1)
    SERIAL=$(echo "$LINE" | awk '{print $4}')
    CERT_PATH=$(echo "$LINE" | awk '{print $NF}')

    if [[ "$STATUS" == "V" && -f "$CERT_PATH" ]]; then
      echo "  [-] Revoking issued certificate serial $SERIAL ($CERT_PATH)..."
      openssl ca -config "$DEPT_CONF" -revoke "$CERT_PATH" -crl_reason cessationOfOperation
    fi
  done < "$DEPT_INDEX"
fi

# 2. Generate updated department CRL
echo "[*] Generating final department CRL..."
openssl ca -config "$DEPT_CONF" -gencrl -out "$DEPT_CRL"

# 3. Revoke department CA certificate at Root level
if [[ -f "$DEPT_CERT" ]]; then
  echo "[*] Revoking department CA certificate in Root CA..."
  openssl ca -config "$ROOT_CONF" -revoke "$DEPT_CERT" -crl_reason cessationOfOperation
fi

# 4. Regenerate Root CRL
echo "[*] Generating updated Root CRL..."
openssl ca -config "$ROOT_CONF" -gencrl -out "$ROOT_DIR/crl/root.crl.pem"

# 5. Sync to ca-server
echo "[*] Syncing to ca-server…"
if [[ -f "scripts/sync_ca_server.sh" ]]; then
  ./scripts/sync_ca_server.sh >/dev/null 2>&1 || true
fi

# 6. Move department CA directory to recycle bin
echo "[*] Moving department CA files to recycle bin..."
mkdir -p "$(dirname "$RECYCLE_DIR")"
mv "$DEPT_DIR" "$RECYCLE_DIR"

echo "[✓] Department '$DEPT' revoked and archived in:"
echo "    $RECYCLE_DIR"

