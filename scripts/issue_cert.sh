#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<EOF
Usage:
  $0 <dept> <profile> <CN> [SANs...]

Profiles:
  server      -> EKU: serverAuth
  client      -> EKU: clientAuth (mTLS, VPN)
  email       -> EKU: emailProtection (S/MIME)
  multipurpose-> EKU: serverAuth,clientAuth,emailProtection (default)

SAN formats:
  DNS:host.example, IP:10.0.0.1, email:user@example.com, URI:spiffe://svc

Examples:
  $0 hq server web1.goldendeals.local DNS:web1.goldendeals.local DNS:alt.goldendeals.local
  $0 hq-personal client "Alice Doe" email:alice@goldendeals.local
  $0 hq email "Security Bot" email:sec-bot@goldendeals.local
EOF
}

DEPT="${1:-}"; shift || true
PROFILE="${1:-multipurpose}"; shift || true
CN="${1:-}"; shift || true
if [[ -z "$DEPT" || -z "$CN" ]]; then usage; exit 1; fi
[[ -n "${PROFILE:-}" ]] || PROFILE="multipurpose"

DEPT_DIR="ca/departments/$DEPT"
CONF="$DEPT_DIR/openssl-$DEPT.cnf"
[[ -f "$CONF" ]] || { echo "Missing dept config: $CONF"; exit 1; }

# Map profile -> extensions section
case "$PROFILE" in
  server)       EXT=server_cert ;;
  vpn-server)   EXT=vpn_server_cert ;;   # <--- added
  client|vpn)   EXT=client_cert ;;
  email)        EXT=email_cert ;;
  multipurpose) EXT=usr_cert ;;
  *) echo "Unknown profile: $PROFILE"; exit 1 ;;
esac

SAFE_CN="$(echo "$CN" | tr -cd '[:alnum:] ._@-')"
STAMP="$(date +%Y%m%d%H%M%S)"
OUT_BASENAME="$DEPT_DIR/certs/${SAFE_CN// /_}__$STAMP"

# Build a small, temporary overlay config for SANs
TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT
cp "$CONF" "$TMP_CONF"

if [[ $# -gt 0 ]]; then
  echo "" >> "$TMP_CONF"
  echo "[ alt_names ]" >> "$TMP_CONF"
  i=1
  for san in "$@"; do
    key="${san%%:*}"
    val="${san#*:}"
    case "$key" in
      DNS|IP|email|URI)
        echo "$key.$i = $val" >> "$TMP_CONF"; i=$((i+1))
        ;;
      *)
        echo "Bad SAN entry '$san' (use DNS: / IP: / email: / URI:)"; exit 1 ;;
    esac
  done
fi

# Generate leaf key and CSR
KEY="$OUT_BASENAME.key.pem"
CSR="$DEPT_DIR/csr/$(basename "$OUT_BASENAME").csr.pem"
CRT="$OUT_BASENAME.cert.pem"

echo "[*] Generating leaf key (RSA-4096)…"
openssl genrsa -out "$KEY" 4096
chmod 600 "$KEY"

echo "[*] Creating CSR…"
openssl req -new -sha256 \
  -key "$KEY" \
  -out "$CSR" \
  -subj "/C=RU/ST=Moscow Oblast/L=Odintsovo/O=Golden Deals LLC/OU=$DEPT/CN=$CN"

echo "[*] Signing certificate with $DEPT CA as $EXT …"
openssl ca -batch -config "$TMP_CONF" \
  -extensions "$EXT" -days 397 -notext -md sha256 \
  -in "$CSR" -out "$CRT"

chmod 644 "$CRT"

# Leaf + chain bundle (useful for servers)
cat "$CRT" "$DEPT_DIR/chain.cert.pem" > "$OUT_BASENAME.fullchain.pem"

echo "[✓] Issued:"
echo "  Key:        $KEY"
echo "  Cert:       $CRT"
echo "  Full chain: $OUT_BASENAME.fullchain.pem"

