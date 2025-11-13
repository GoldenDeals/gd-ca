#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# update-public.sh
#   Creates certificate bundle (Root CA + all Department CAs)
#   and CRL bundle (Root CRL + all Department CRLs)
#   and places them in the ./public folder
#   Individual CRLs are also copied to ./public/crl/
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
CRL_DIR="$PUBLIC_DIR/crl"

# --- Ensure public directories exist ---
mkdir -p "$PUBLIC_DIR"
mkdir -p "$CRL_DIR"

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
    cert_count=$((cert_count + 1))
  else
    echo "  ! Warning: Certificate not found for department $dept_name" >&2
  fi
done

echo "[OK] CA bundle created: $CA_BUNDLE ($cert_count certificates)"

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
    crl_count=$((crl_count + 1))
  else
    echo "  ! Warning: CRL not found for department $dept_name" >&2
  fi
done

echo "[OK] CRL bundle created: $CRL_BUNDLE ($crl_count CRLs)"

# --- Copy individual CRLs to public/crl/ ---
echo "[*] Copying individual CRLs..."

# Copy root CRL
if [[ -f "$ROOT_CRL" ]]; then
  cp "$ROOT_CRL" "$CRL_DIR/root.crl.pem"
  echo "  + Copied root.crl.pem"
fi

# Copy all department CRLs
individual_count=1
for dept_dir in "$DEPT_BASE"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  
  dept_name=$(basename "$dept_dir")
  dept_crl="$dept_dir/crl/$dept_name.crl.pem"
  
  if [[ -f "$dept_crl" ]]; then
    cp "$dept_crl" "$CRL_DIR/$dept_name.crl.pem"
    echo "  + Copied $dept_name.crl.pem"
    individual_count=$((individual_count + 1))
  fi
done

echo "[OK] Individual CRLs copied: $individual_count files in $CRL_DIR/"

# --- Summary ---
echo ""
echo "=========================================="
echo "  Public bundles updated successfully"
echo "=========================================="
echo ""
echo "  CA Bundle:       $CA_BUNDLE"
echo "  CRL Bundle:      $CRL_BUNDLE"
echo "  Individual CRLs: $CRL_DIR/"
echo ""
