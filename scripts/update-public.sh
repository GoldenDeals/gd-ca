#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# update-public.sh
#   Creates certificate bundle (Root CA + all Department CAs)
#   Individual CA certificates are copied to ./public/certs/
#   Individual CRLs are copied to ./public/crl/
#
#   Usage:
#     ./scripts/update-public.sh
# ============================================================

ROOT_CERT="ca/root/root.cert.pem"
ROOT_CRL="ca/root/crl/root.crl.pem"
DEPT_BASE="ca/departments"
PUBLIC_DIR="public"

CA_BUNDLE="$PUBLIC_DIR/bundle.pem"
CERT_DIR="$PUBLIC_DIR/certs"
CRL_DIR="$PUBLIC_DIR/crl"

# --- Ensure public directories exist ---
mkdir -p "$PUBLIC_DIR"
mkdir -p "$CERT_DIR"
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

# --- Copy individual CA certificates to public/certs/ ---
echo "[*] Copying individual CA certificates..."

# Copy root CA certificate
if [[ -f "$ROOT_CERT" ]]; then
  cp "$ROOT_CERT" "$CERT_DIR/root.cert.pem"
  echo "  + Copied root.cert.pem"
fi

# Copy all department CA certificates
individual_cert_count=1
for dept_dir in "$DEPT_BASE"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  
  dept_name=$(basename "$dept_dir")
  dept_cert="$dept_dir/ca.cert.pem"
  
  if [[ -f "$dept_cert" ]]; then
    cp "$dept_cert" "$CERT_DIR/$dept_name.cert.pem"
    echo "  + Copied $dept_name.cert.pem"
    individual_cert_count=$((individual_cert_count + 1))
  fi
done

echo "[OK] Individual CA certificates copied: $individual_cert_count files in $CERT_DIR/"

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
echo "  Public files updated successfully"
echo "=========================================="
echo ""
echo "  CA Bundle:          $CA_BUNDLE"
echo "  Individual Certs:   $CERT_DIR/"
echo "  Individual CRLs:    $CRL_DIR/"
echo ""
