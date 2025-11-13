#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# update-public.sh
#   Creates certificate bundle (Root CA + all Department CAs)
#   and CRL bundle (Root CRL + all Department CRLs)
#   and places them in the ./public folder
#
#   Usage:
#     ./scripts/update-public.sh
# ============================================================

ROOT_CERT="ca/root/root.cert.pem"
ROOT_CRL="ca/root/crl/root.crl.pem"
DEPT_BASE="ca/departments"
PUBLIC_DIR="public"

CA_BUNDLE="$PUBLIC_DIR/ca-bundle.pem"
CRL_BUNDLE="$PUBLIC_DIR/crl-bundle.pem"

# --- Ensure public directory exists ---
mkdir -p "$PUBLIC_DIR"

# --- Create CA certificate bundle ---
echo "[*] Creating CA certificate bundle..."

if [[ ! -f "$ROOT_CERT" ]]; then
  echo "[ERROR] Root CA certificate not found: $ROOT_CERT" >&2
  exit 1
fi

# Start with root CA
cat "$ROOT_CERT" > "$CA_BUNDLE"
echo "" >> "$CA_BUNDLE"

# Add all department CA certificates
cert_count=1
for dept_dir in "$DEPT_BASE"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  
  dept_name=$(basename "$dept_dir")
  dept_cert="$dept_dir/ca.cert.pem"
  
  if [[ -f "$dept_cert" ]]; then
    echo "  + Adding $dept_name CA certificate"
    cat "$dept_cert" >> "$CA_BUNDLE"
    echo "" >> "$CA_BUNDLE"
    ((cert_count++))
  else
    echo "  ! Warning: Certificate not found for department $dept_name" >&2
  fi
done

echo "[✓] CA bundle created: $CA_BUNDLE ($cert_count certificates)"

# --- Create CRL bundle ---
echo "[*] Creating CRL bundle..."

if [[ ! -f "$ROOT_CRL" ]]; then
  echo "[ERROR] Root CRL not found: $ROOT_CRL" >&2
  exit 1
fi

# Start with root CRL
cat "$ROOT_CRL" > "$CRL_BUNDLE"
echo "" >> "$CRL_BUNDLE"

# Add all department CRLs
crl_count=1
for dept_dir in "$DEPT_BASE"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  
  dept_name=$(basename "$dept_dir")
  dept_crl="$dept_dir/crl/$dept_name.crl.pem"
  
  if [[ -f "$dept_crl" ]]; then
    echo "  + Adding $dept_name CRL"
    cat "$dept_crl" >> "$CRL_BUNDLE"
    echo "" >> "$CRL_BUNDLE"
    ((crl_count++))
  else
    echo "  ! Warning: CRL not found for department $dept_name" >&2
  fi
done

echo "[✓] CRL bundle created: $CRL_BUNDLE ($crl_count CRLs)"

# --- Summary ---
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  Public bundles updated successfully       ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  CA Bundle:  $CA_BUNDLE"
echo "  CRL Bundle: $CRL_BUNDLE"
echo ""

