#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# list_certs.sh
#   List all certificates in all department CAs (pretty table or JSON)
#   Usage:
#     ./scripts/list_certs.sh [--dept <name>] [--valid|--revoked|--expired] [--json]
#     ./scripts/list_certs.sh <composite-id>   # detailed info
# ============================================================

shopt -s nullglob
BASE_DIR="ca/departments"
FORMAT="table"
FILTER="all"
DEPT_FILTER=""
DETAIL_ID=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT="json";;
    --valid|--revoked|--expired) FILTER="${1#--}";;
    --dept) shift; DEPT_FILTER="${1:-}";;
    -d) shift; DEPT_FILTER="${1:-}";;
    -h|--help)
      echo "Usage:"
      echo "  $0 [--dept <name>] [--valid|--revoked|--expired] [--json]"
      echo "  $0 <composite-id>   # Show details of a single certificate"
      exit 0;;
    *)
      if [[ -z "$DETAIL_ID" ]]; then DETAIL_ID="$1"; else echo "Unexpected arg: $1"; exit 1; fi;;
  esac
  shift
done

# --- Show details for one cert ---
show_cert_details() {
  local composite="$1"
  local cert_serial="${composite##*-}"
  local dept="${composite%-${cert_serial}}"
  local dept_dir="$BASE_DIR/$dept"

  if [[ ! -d "$dept_dir" ]]; then
    echo "Department '$dept' not found" >&2; exit 1
  fi

  local cert_path
  cert_path=$(grep -E "\b${cert_serial}\b" "$dept_dir/index.txt" | awk -F'\t' '{print $5}' | tail -1)

  if [[ -z "$cert_path" || "$cert_path" == "unknown" ]]; then
    cert_path="$dept_dir/newcerts/$cert_serial.pem"
  fi

  if [[ ! -f "$cert_path" ]]; then
    echo "Certificate with serial $composite not found." >&2
    exit 1
  fi

  echo "=== Certificate: $composite ==="
  openssl x509 -in "$cert_path" -noout -text
  exit 0
}

# If user passed <dept>-<serial>, show details
if [[ "$DETAIL_ID" =~ ^[a-zA-Z0-9._-]+-[0-9]+$ ]]; then
  show_cert_details "$DETAIL_ID"
fi

declare -A STATUS_LABELS=( ["V"]="Valid" ["R"]="Revoked" ["E"]="Expired" )
RESULTS=()

# --- Helper: format OpenSSL date + remaining days ---
format_expiry() {
  local raw="$1"
  # Expected format like 261031235959Z (YYMMDDHHMMSSZ)
  # Convert to full year
  local yy="${raw:0:2}"
  local year=$((2000 + 10#$yy))
  local month="${raw:2:2}"
  local day="${raw:4:2}"
  local hour="${raw:6:2}"
  local min="${raw:8:2}"
  local sec="${raw:10:2}"

  local iso="${year}-${month}-${day} ${hour}:${min}:${sec}"
  local epoch_exp
  epoch_exp=$(date -d "$iso" +%s 2>/dev/null || echo 0)
  local epoch_now
  epoch_now=$(date +%s)

  local diff_days=$(( (epoch_exp - epoch_now) / 86400 ))
  [[ $diff_days -lt 0 ]] && diff_days=0

  local human_date
  human_date=$(date -d "$iso" +"%H:%M %d-%m-%Y" 2>/dev/null || echo "$iso")

  printf "%s (%3dd left)" "$human_date" "$diff_days"
}

# --- Collect all certs ---
for dept_dir in "$BASE_DIR"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  dept=$(basename "$dept_dir")
  [[ -n "$DEPT_FILTER" && "$dept" != "$DEPT_FILTER" ]] && continue
  index="$dept_dir/index.txt"
  [[ ! -f "$index" ]] && continue

  while read -r line; do
    [[ -z "$line" ]] && continue
    status=${line:0:1}
    exp_date=$(echo "$line" | awk -F'\t' '{print $2}')
    serial=$(echo "$line" | awk -F'\t' '{print $4}')
    cert_path=$(echo "$line" | awk -F'\t' '{print $5}')
    subject_dn=$(echo "$line" | awk -F'\t' '{print $6}')
    
    cn="unknown"
    if [[ -n "$subject_dn" ]]; then
      cn=$(echo "$subject_dn" | sed -E 's|.*/CN=([^/]+).*|\1|' || echo "unknown")
    fi
    
    if [[ "$cn" == "unknown" && "$cert_path" != "unknown" && -f "$cert_path" ]]; then
      cn=$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed -E 's/.*CN=([^,]+).*/\1/' | sed 's/^subject=//' || echo "unknown")
    elif [[ "$cn" == "unknown" && -f "$dept_dir/newcerts/$serial.pem" ]]; then
      cn=$(openssl x509 -in "$dept_dir/newcerts/$serial.pem" -noout -subject 2>/dev/null | sed -E 's/.*CN=([^,]+).*/\1/' | sed 's/^subject=//' || echo "unknown")
      cert_path="$dept_dir/newcerts/$serial.pem"
    fi

    if [[ "$cert_path" == "unknown" && -f "$dept_dir/newcerts/$serial.pem" ]]; then
      cert_path="$dept_dir/newcerts/$serial.pem"
    fi

    # Derive Expired status
    if [[ "$status" == "V" ]]; then
      exp_epoch=$(date -d "$(echo "$exp_date" | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*/20\1-\2-\3 \4:\5:\6/')" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      (( now_epoch > exp_epoch )) && status="E"
    fi

    case "$FILTER" in
      valid)   [[ "$status" != "V" ]] && continue ;;
      revoked) [[ "$status" != "R" ]] && continue ;;
      expired) [[ "$status" != "E" ]] && continue ;;
    esac

    expiry_fmt=$(format_expiry "$exp_date")
    id="${dept}-${serial}"
    RESULTS+=("$id|$dept|${STATUS_LABELS[$status]}|$expiry_fmt|$cn|$cert_path")
  done <"$index"
done

# --- Output ---
if [[ "$FORMAT" == "json" ]]; then
  echo "["
  first=1
  for entry in "${RESULTS[@]}"; do
    IFS="|" read -r id dept status exp cn path <<<"$entry"
    [[ $first -eq 0 ]] && echo ","
    first=0
    jq -n \
      --arg id "$id" --arg dept "$dept" --arg status "$status" \
      --arg exp "$exp" --arg cn "$cn" --arg path "$path" \
      '{id:$id,department:$dept,status:$status,expiry:$exp,common_name:$cn,cert_path:$path}'
  done
  echo "]"
else
  max_id_len=2
  max_dept_len=10
  max_status_len=6
  max_exp_len=6
  max_cn_len=12
  max_path_len=4
  
  for entry in "${RESULTS[@]}"; do
    IFS="|" read -r id dept status exp cn path <<<"$entry"
    [[ ${#id} -gt $max_id_len ]] && max_id_len=${#id}
    [[ ${#dept} -gt $max_dept_len ]] && max_dept_len=${#dept}
    [[ ${#status} -gt $max_status_len ]] && max_status_len=${#status}
    [[ ${#exp} -gt $max_exp_len ]] && max_exp_len=${#exp}
    [[ ${#cn} -gt $max_cn_len ]] && max_cn_len=${#cn}
    [[ ${#path} -gt $max_path_len ]] && max_path_len=${#path}
  done
  
  header_id="ID"
  header_dept="Department"
  header_status="Status"
  header_exp="Expiry"
  header_cn="Common Name"
  header_path="Path"
  
  max_id_len=$((max_id_len > ${#header_id} ? max_id_len : ${#header_id}))
  max_dept_len=$((max_dept_len > ${#header_dept} ? max_dept_len : ${#header_dept}))
  max_status_len=$((max_status_len > ${#header_status} ? max_status_len : ${#header_status}))
  max_exp_len=$((max_exp_len > ${#header_exp} ? max_exp_len : ${#header_exp}))
  max_cn_len=$((max_cn_len > ${#header_cn} ? max_cn_len : ${#header_cn}))
  
  printf "%-*s | %-*s | %-*s | %-*s | %-*s | %s\n" \
    "$max_id_len" "$header_id" \
    "$max_dept_len" "$header_dept" \
    "$max_status_len" "$header_status" \
    "$max_exp_len" "$header_exp" \
    "$max_cn_len" "$header_cn" \
    "$header_path"
  
  total_width=$((max_id_len + max_dept_len + max_status_len + max_exp_len + max_cn_len + max_path_len + 15))
  printf "%*s\n" "$total_width" "" | tr ' ' '-'
  
  for entry in "${RESULTS[@]}"; do
    IFS="|" read -r id dept status exp cn path <<<"$entry"
    printf "%-*s | %-*s | %-*s | %-*s | %-*s | %s\n" \
      "$max_id_len" "$id" \
      "$max_dept_len" "$dept" \
      "$max_status_len" "$status" \
      "$max_exp_len" "$exp" \
      "$max_cn_len" "$cn" \
      "$path"
  done
fi

