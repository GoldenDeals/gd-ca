#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================
# sign_csr.sh
#   Verify and sign a Certificate Signing Request (CSR) with a department CA
#   
#   Usage:
#     ./scripts/sign_csr.sh <dept> <profile> <csr_file> [SANs...]
#
#   Profiles:
#     server      -> EKU: serverAuth
#     vpn-server  -> EKU: serverAuth, clientAuth
#     client      -> EKU: clientAuth (mTLS, VPN)
#     email       -> EKU: emailProtection (S/MIME)
#     multipurpose-> EKU: serverAuth,clientAuth,emailProtection (default)
#
#   Examples:
#     ./scripts/sign_csr.sh hq server /path/to/web.csr.pem
#     ./scripts/sign_csr.sh hq-personal client /path/to/user.csr.pem
#     ./scripts/sign_csr.sh hq server /path/to/web.csr.pem DNS:alt.example.com
# ============================================================

usage() {
  cat <<EOF
Usage: $0 <dept> <profile> <csr_file> [SANs...]

Signs a Certificate Signing Request with a department CA.

Arguments:
  dept       Department name (e.g., hq, hq-personal)
  profile    Certificate profile (server, client, email, multipurpose, vpn-server)
  csr_file   Path to the CSR file to sign
  SANs       Additional Subject Alternative Names (optional)
             Format: TYPE:value (e.g., DNS:host.example.com)

Profiles:
  server      -> EKU: serverAuth
  vpn-server  -> EKU: serverAuth, clientAuth
  client      -> EKU: clientAuth (mTLS, VPN)
  email       -> EKU: emailProtection (S/MIME)
  multipurpose-> EKU: serverAuth,clientAuth,emailProtection (default)

Examples:
  $0 hq server /path/to/web.csr.pem
  $0 hq-personal client /path/to/user.csr.pem
  $0 hq server /path/to/web.csr.pem DNS:alt.example.com DNS:www.example.com
EOF
}

DEPT="${1:-}"
PROFILE="${2:-}"
CSR_FILE="${3:-}"

if [[ -z "$DEPT" || -z "$PROFILE" || -z "$CSR_FILE" ]]; then
  usage
  exit 1
fi

shift 3 || true

DEPT_DIR="ca/departments/$DEPT"
CONF="$DEPT_DIR/openssl-$DEPT.cnf"

if [[ ! -d "$DEPT_DIR" ]]; then
  echo "Error: Department '$DEPT' not found" >&2
  exit 1
fi

if [[ ! -f "$CONF" ]]; then
  echo "Error: Missing department config: $CONF" >&2
  exit 1
fi

if [[ ! -f "$CSR_FILE" ]]; then
  echo "Error: CSR file not found: $CSR_FILE" >&2
  exit 1
fi

case "$PROFILE" in
  server)       EXT=server_cert ;;
  vpn-server)   EXT=vpn_server_cert ;;
  client|vpn)   EXT=client_cert ;;
  email)        EXT=email_cert ;;
  multipurpose) EXT=usr_cert ;;
  *)
    echo "Error: Unknown profile: $PROFILE" >&2
    echo "       Valid profiles: server, vpn-server, client, email, multipurpose" >&2
    exit 1
    ;;
esac

echo "[*] Verifying CSR..."
if ! openssl req -in "$CSR_FILE" -noout -verify >/dev/null 2>&1; then
  echo "Error: CSR verification failed. The CSR file may be corrupted or invalid." >&2
  exit 1
fi

echo "[*] CSR details:"
openssl req -in "$CSR_FILE" -noout -text -nameopt sep_multiline,utf8 | grep -A 20 "Subject:"

CN=$(openssl req -in "$CSR_FILE" -noout -subject | sed -E 's/.*CN=([^/]+).*/\1/')
if [[ -z "$CN" ]]; then
  CN=$(openssl req -in "$CSR_FILE" -noout -subject | sed -E 's/.*CN=([^,]+).*/\1/')
fi

if [[ -z "$CN" ]]; then
  echo "Warning: Could not extract CN from CSR, using default name" >&2
  CN="cert_$(date +%Y%m%d%H%M%S)"
fi

SAFE_CN="$(echo "$CN" | tr -cd '[:alnum:] ._@-')"
STAMP="$(date +%Y%m%d%H%M%S)"
OUT_BASENAME="$DEPT_DIR/certs/${SAFE_CN// /_}__$STAMP"
CRT="$OUT_BASENAME.cert.pem"

TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT
cp "$CONF" "$TMP_CONF"

SAN_COUNT=0
if [[ $# -gt 0 ]]; then
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
        SAN_COUNT=$i
        ;;
      *)
        echo "Error: Invalid SAN format '$san'" >&2
        echo "       Use format: TYPE:value (e.g., DNS:host.example.com)" >&2
        exit 1
        ;;
    esac
  done
fi

if [[ $SAN_COUNT -eq 0 ]]; then
  CSR_SANS=$(openssl req -in "$CSR_FILE" -noout -text 2>/dev/null | grep -A 1 "X509v3 Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//' || echo "")
  if [[ -n "$CSR_SANS" ]]; then
    echo "" >> "$TMP_CONF"
    echo "[ alt_names ]" >> "$TMP_CONF"
    i=1
    TMP_SANS="$(mktemp)"
    echo "$CSR_SANS" | sed 's/, /\n/g' > "$TMP_SANS"
    while IFS= read -r san_entry; do
      [[ -z "$san_entry" ]] && continue
      if [[ "$san_entry" =~ ^DNS: ]]; then
        echo "DNS.$i = ${san_entry#DNS:}" >> "$TMP_CONF"
        i=$((i+1))
      elif [[ "$san_entry" =~ ^IP: ]]; then
        echo "IP.$i = ${san_entry#IP:}" >> "$TMP_CONF"
        i=$((i+1))
      elif [[ "$san_entry" =~ ^email: ]]; then
        echo "email.$i = ${san_entry#email:}" >> "$TMP_CONF"
        i=$((i+1))
      elif [[ "$san_entry" =~ ^URI: ]]; then
        echo "URI.$i = ${san_entry#URI:}" >> "$TMP_CONF"
        i=$((i+1))
      fi
    done < "$TMP_SANS"
    rm -f "$TMP_SANS"
  fi
fi

echo "[*] Signing certificate with $DEPT CA as $EXT..."
if ! openssl ca -batch -config "$TMP_CONF" \
  -extensions "$EXT" -days 397 -notext -md sha256 \
  -in "$CSR_FILE" -out "$CRT" 2>&1; then
  echo "Error: Failed to sign certificate" >&2
  exit 1
fi

chmod 644 "$CRT"

cat "$CRT" "$DEPT_DIR/chain.cert.pem" > "$OUT_BASENAME.fullchain.pem"

echo ""
echo "[✓] Certificate signed successfully!"
echo ""
echo "  Certificate: $CRT"
echo "  Full chain:  $OUT_BASENAME.fullchain.pem"
echo ""
echo "[*] Certificate details:"
openssl x509 -in "$CRT" -noout -text -nameopt sep_multiline,utf8 | grep -A 5 "Subject:\|Issuer:\|Validity"

