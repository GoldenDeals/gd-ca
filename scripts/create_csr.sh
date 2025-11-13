#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================
# create_csr.sh
#   Standalone script to generate a Certificate Signing Request (CSR)
#   This script can be distributed to users to create CSRs
#   
#   Usage:
#     ./create_csr.sh <CN> [SANs...]
#   
#   SAN formats:
#     DNS:host.example.com
#     IP:10.0.0.1
#     email:user@example.com
#     URI:spiffe://service/name
#
#   Examples:
#     ./create_csr.sh "web.example.com" DNS:web.example.com DNS:www.example.com
#     ./create_csr.sh "user@example.com" email:user@example.com
#     ./create_csr.sh "10.0.0.1" IP:10.0.0.1
# ============================================================

usage() {
  cat <<EOF
Usage: $0 <CN> [SANs...]

Creates a Certificate Signing Request (CSR) and private key.

Arguments:
  CN          Common Name (required)
  SANs        Subject Alternative Names (optional)
              Format: TYPE:value (e.g., DNS:host.example.com, IP:10.0.0.1)

Examples:
  $0 "web.example.com" DNS:web.example.com DNS:www.example.com
  $0 "user@example.com" email:user@example.com
  $0 "server" DNS:server.example.com IP:192.168.1.100

Output files:
  <CN>_<timestamp>.key.pem  - Private key (keep secure!)
  <CN>_<timestamp>.csr.pem  - Certificate Signing Request (send to CA)
EOF
}

CN="${1:-}"
if [[ -z "$CN" ]]; then
  usage
  exit 1
fi
shift || true

SAFE_CN="$(echo "$CN" | tr -cd '[:alnum:] ._@-')"
STAMP="$(date +%Y%m%d%H%M%S)"
KEY_FILE="${SAFE_CN// /_}_${STAMP}.key.pem"
CSR_FILE="${SAFE_CN// /_}_${STAMP}.csr.pem"

TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT

cat > "$TMP_CONF" <<EOF
[ req ]
default_bits        = 4096
default_md          = sha256
string_mask         = utf8only
prompt              = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C  = RU
ST = Moscow Oblast
L  = Odintsovo
O  = Golden Deals LLC
CN = $CN

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
EOF

if [[ $# -gt 0 ]]; then
  echo "subjectAltName = @alt_names" >> "$TMP_CONF"
  echo "" >> "$TMP_CONF"
  echo "[ alt_names ]" >> "$TMP_CONF"
  i=1
  for san in "$@"; do
    key="${san%%:*}"
    val="${san#*:}"
    case "$key" in
      DNS|IP|email|URI)
        echo "$key.$i = $val" >> "$TMP_CONF"
        i=$((i+1))
        ;;
      *)
        echo "Error: Invalid SAN format '$san'" >&2
        echo "       Use format: TYPE:value (e.g., DNS:host.example.com)" >&2
        exit 1
        ;;
    esac
  done
fi

echo "[*] Generating private key (RSA-4096)..."
openssl genrsa -out "$KEY_FILE" 4096
chmod 600 "$KEY_FILE"

echo "[*] Creating Certificate Signing Request..."
openssl req -new -sha256 \
  -key "$KEY_FILE" \
  -out "$CSR_FILE" \
  -config "$TMP_CONF"

chmod 644 "$CSR_FILE"

echo ""
echo "[✓] CSR created successfully!"
echo ""
echo "  Private Key: $KEY_FILE"
echo "  CSR:         $CSR_FILE"
echo ""
echo "  IMPORTANT: Keep the private key secure and private!"
echo "             Send only the CSR file ($CSR_FILE) to your CA administrator."
echo ""
echo "[*] CSR details:"
openssl req -in "$CSR_FILE" -noout -text -nameopt sep_multiline,utf8 | grep -A 20 "Subject:"

if [[ $# -gt 0 ]]; then
  echo ""
  echo "[*] Subject Alternative Names:"
  openssl req -in "$CSR_FILE" -noout -text | grep -A 10 "X509v3 Subject Alternative Name" || true
fi


