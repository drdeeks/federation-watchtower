#!/usr/bin/env bash
# Configuration helpers (JSON via jq) and host ID generation

if [[ -n "${UCA_CONFIG_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_CONFIG_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"

: "${UCA_CONFIG_DIR:=$HOME/.config/usb-compute-automation}"
: "${UCA_CONFIG_FILE:=$UCA_CONFIG_DIR/config.json}"

config_init() {
  mkdir -p "$UCA_CONFIG_DIR" 2>/dev/null || true
  if [[ ! -f "$UCA_CONFIG_FILE" ]]; then
    printf '{"version":"1.0.0","last_updated":"%s","installations":{}}\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$UCA_CONFIG_FILE" 2>/dev/null || true
  fi
}

config_get() {
  # Usage: config_get .path.to.key
  command -v jq >/dev/null 2>&1 || { print_error "jq not installed"; return 1; }
  jq -r "$1 // empty" "$UCA_CONFIG_FILE" 2>/dev/null
}

config_set() {
  # Usage: config_set .path.to.key value_json
  command -v jq >/dev/null 2>&1 || { print_error "jq not installed"; return 1; }
  local path="$1"; shift
  local value="$1"
  local tmp; tmp=$(mktemp)
  jq "$path = $value | .last_updated = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" \
    "$UCA_CONFIG_FILE" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$UCA_CONFIG_FILE"
}

generate_host_id() {
  # Creates/updates host ID section in config
  command -v jq >/dev/null 2>&1 || { print_error "jq not installed"; return 1; }
  local hostname mac ip os kernel
  hostname=$(hostname 2>/dev/null || echo unknown)
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo unknown)
  if command -v ip >/dev/null 2>&1; then
    mac=$(ip link show 2>/dev/null | awk '/link\/ether/{print $2; exit}')
  else
    mac=unknown
  fi
  os=$(uname -s 2>/dev/null || echo unknown)
  kernel=$(uname -r 2>/dev/null || echo unknown)
  local host_id
  host_id=$(printf '%s-%s' "$hostname" "$mac" | md5sum 2>/dev/null | awk '{print $1}' | cut -c1-8)
  local json
  json=$(cat <<EOF
{
  "host_id": "usb-compute-$host_id",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$hostname",
  "mac_address": "$mac",
  "ip_address": "$ip",
  "os_info": "$os",
  "kernel_version": "$kernel"
}
EOF
)
  local tmp; tmp=$(mktemp)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --argjson host "$json" --arg ts "$timestamp" '.host_id = $host | .last_updated = $ts' \
    "$UCA_CONFIG_FILE" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$UCA_CONFIG_FILE"
  print_success "Host identification generated: usb-compute-$host_id"
}
