#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# list_departments.sh
#   Lists all department CAs (active and revoked)
#   Usage:
#     ./scripts/list_departments.sh [--json] [--stats]
# ============================================================

BASE_DIR="ca/departments"
RECYCLE_DIR="ca/recycle-bin"
FORMAT="table"
WITH_STATS="false"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT="json";;
    --stats) WITH_STATS="true";;
    -h|--help)
      echo "Usage:"
      echo "  $0 [--json] [--stats]"
      echo
      echo "Options:"
      echo "  --json   Output in JSON"
      echo "  --stats  Include valid/revoked/expired cert counts per department and totals"
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift
done

# --- Helper: Count certs by status ---
count_certs() {
  local dept_dir="$1"
  local valid=0 revoked=0 expired=0
  local index="$dept_dir/index.txt"
  [[ ! -f "$index" ]] && { echo "0|0|0"; return; }

  while read -r line; do
    [[ -z "$line" ]] && continue
    local s="${line:0:1}"
    case "$s" in
      V)
        local exp_date
        exp_date=$(echo "$line" | awk '{print $2}')
        local exp_epoch now_epoch
        exp_epoch=$(date -d "$(echo "$exp_date" | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*/20\1-\2-\3 \4:\5:\6/')" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if (( now_epoch > exp_epoch )); then ((expired++)); else ((valid++)); fi ;;
      R) ((revoked++));;
    esac
  done <"$index"

  echo "${valid}|${revoked}|${expired}"
}

# --- Collect all departments ---
DEPARTMENTS=()
TOTAL_VALID=0
TOTAL_REVOKED=0
TOTAL_EXPIRED=0

for dept_dir in "$BASE_DIR"/*; do
  [[ ! -d "$dept_dir" ]] && continue
  dept=$(basename "$dept_dir")
  cert="$dept_dir/ca.cert.pem"
  key="$dept_dir/private/ca.key.pem"

  valid_label="Yes"
  [[ ! -f "$cert" || ! -f "$key" ]] && valid_label="Broken"

  stats=""
  if [[ "$WITH_STATS" == "true" ]]; then
    IFS="|" read -r valid revoked expired <<<"$(count_certs "$dept_dir")"
    stats="Valid=$valid, Revoked=$revoked, Expired=$expired"
    TOTAL_VALID=$((TOTAL_VALID + valid))
    TOTAL_REVOKED=$((TOTAL_REVOKED + revoked))
    TOTAL_EXPIRED=$((TOTAL_EXPIRED + expired))
  fi

  DEPARTMENTS+=("$dept|Active|$valid_label|$stats|$dept_dir")
done

for rec_dir in "$RECYCLE_DIR"/*; do
  [[ ! -d "$rec_dir" ]] && continue
  dept=$(basename "$rec_dir")
  DEPARTMENTS+=("$dept|Revoked|Archived|-|$rec_dir")
done

# --- Output ---
if [[ "$FORMAT" == "json" ]]; then
  echo "["
  first=1
  for entry in "${DEPARTMENTS[@]}"; do
    IFS="|" read -r name status integrity stats path <<<"$entry"
    [[ $first -eq 0 ]] && echo ","
    first=0
    jq -n \
      --arg name "$name" --arg status "$status" --arg integrity "$integrity" \
      --arg stats "$stats" --arg path "$path" \
      '{name:$name,status:$status,integrity:$integrity,stats:$stats,dir:$path}'
  done
  echo "]"

  if [[ "$WITH_STATS" == "true" ]]; then
    jq -n \
      --arg total_valid "$TOTAL_VALID" \
      --arg total_revoked "$TOTAL_REVOKED" \
      --arg total_expired "$TOTAL_EXPIRED" \
      '{summary:{total_valid:($total_valid|tonumber), total_revoked:($total_revoked|tonumber), total_expired:($total_expired|tonumber)}}'
  fi
else
  max_name_len=10
  max_status_len=6
  max_integrity_len=9
  max_stats_len=0
  max_path_len=4
  
  for entry in "${DEPARTMENTS[@]}"; do
    IFS="|" read -r name status integrity stats path <<<"$entry"
    [[ ${#name} -gt $max_name_len ]] && max_name_len=${#name}
    [[ ${#status} -gt $max_status_len ]] && max_status_len=${#status}
    [[ ${#integrity} -gt $max_integrity_len ]] && max_integrity_len=${#integrity}
    [[ ${#stats} -gt $max_stats_len ]] && max_stats_len=${#stats}
    [[ ${#path} -gt $max_path_len ]] && max_path_len=${#path}
  done
  
  header_name="Department"
  header_status="Status"
  header_integrity="Integrity"
  header_stats="Stats"
  header_path="Path"
  
  max_name_len=$((max_name_len > ${#header_name} ? max_name_len : ${#header_name}))
  max_status_len=$((max_status_len > ${#header_status} ? max_status_len : ${#header_status}))
  max_integrity_len=$((max_integrity_len > ${#header_integrity} ? max_integrity_len : ${#header_integrity}))
  if [[ "$WITH_STATS" == "true" ]]; then
    max_stats_len=$((max_stats_len > ${#header_stats} ? max_stats_len : ${#header_stats}))
  fi
  
  if [[ "$WITH_STATS" == "true" ]]; then
    printf "%-*s | %-*s | %-*s | %-*s | %s\n" \
      "$max_name_len" "$header_name" \
      "$max_status_len" "$header_status" \
      "$max_integrity_len" "$header_integrity" \
      "$max_stats_len" "$header_stats" \
      "$header_path"
    
    total_width=$((max_name_len + max_status_len + max_integrity_len + max_stats_len + max_path_len + 12))
    printf "%*s\n" "$total_width" "" | tr ' ' '-'
    
    for entry in "${DEPARTMENTS[@]}"; do
      IFS="|" read -r name status integrity stats path <<<"$entry"
      printf "%-*s | %-*s | %-*s | %-*s | %s\n" \
        "$max_name_len" "$name" \
        "$max_status_len" "$status" \
        "$max_integrity_len" "$integrity" \
        "$max_stats_len" "$stats" \
        "$path"
    done
    
    printf "%*s\n" "$total_width" "" | tr ' ' '-'
    printf "TOTALS: Valid=%d  Revoked=%d  Expired=%d  (Total=%d)\n" \
      "$TOTAL_VALID" "$TOTAL_REVOKED" "$TOTAL_EXPIRED" "$((TOTAL_VALID + TOTAL_REVOKED + TOTAL_EXPIRED))"
  else
    printf "%-*s | %-*s | %-*s | %s\n" \
      "$max_name_len" "$header_name" \
      "$max_status_len" "$header_status" \
      "$max_integrity_len" "$header_integrity" \
      "$header_path"
    
    total_width=$((max_name_len + max_status_len + max_integrity_len + max_path_len + 9))
    printf "%*s\n" "$total_width" "" | tr ' ' '-'
    
    for entry in "${DEPARTMENTS[@]}"; do
      IFS="|" read -r name status integrity stats path <<<"$entry"
      printf "%-*s | %-*s | %-*s | %s\n" \
        "$max_name_len" "$name" \
        "$max_status_len" "$status" \
        "$max_integrity_len" "$integrity" \
        "$path"
    done
  fi
fi

