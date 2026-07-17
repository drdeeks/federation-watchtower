#!/usr/bin/env bash
# Test 04: Configuration (init, get, set, host-id)
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing configuration system..."

# Backup existing config
CONFIG_DIR="$HOME/.config/usb-compute-automation"
CONFIG_FILE="$CONFIG_DIR/config.json"
BACKUP=""
[[ -f "$CONFIG_FILE" ]] && BACKUP=$(cp "$CONFIG_FILE" "$CONFIG_FILE.bak-test-$$" && echo "$CONFIG_FILE.bak-test-$$")

# Test config_init
if config_init 2>/dev/null; then
  assert_pass "config_init succeeds"
else
  assert_fail "config_init failed"
fi

# Test config file exists
assert_file_exists "$CONFIG_FILE" "config.json created"

# Test config is valid JSON
if [[ -f "$CONFIG_FILE" ]]; then
  assert_json_valid "$CONFIG_FILE" "config.json is valid JSON"
fi

# Test config_get
version=$(config_get '.version' 2>/dev/null)
if [[ -n "$version" && "$version" != "null" ]]; then
  assert_pass "config_get .version = $version"
else
  assert_fail "config_get .version returned empty/null"
fi

# Test generate_host_id
if generate_host_id 2>/dev/null; then
  assert_pass "generate_host_id succeeds"
else
  assert_fail "generate_host_id failed"
fi

# Test host_id is in config
host_id=$(config_get '.host_id.host_id' 2>/dev/null)
if [[ -n "$host_id" && "$host_id" == usb-compute-* ]]; then
  assert_pass "host_id = $host_id"
else
  assert_fail "host_id invalid" "Got: $host_id"
fi

# Test host_id fields exist
for field in hostname mac_address ip_address os_info kernel_version; do
  val=$(config_get ".host_id.$field" 2>/dev/null)
  if [[ -n "$val" && "$val" != "null" ]]; then
    assert_pass "host_id.$field populated"
  else
    assert_fail "host_id.$field missing"
  fi
done

# Restore backup
[[ -n "$BACKUP" && -f "$BACKUP" ]] && mv "$BACKUP" "$CONFIG_FILE"
rm -f "$CONFIG_FILE.bak-test-$$" 2>/dev/null

log INFO "Config tests complete"
