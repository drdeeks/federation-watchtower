#!/usr/bin/env bash
# Stack-based menu framework (scaffold)

if [[ -n "${UCA_MENU_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_MENU_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"

declare -ag UCA_MENU_STACK=()

menu_current() {
  local n=${#UCA_MENU_STACK[@]}
  (( n == 0 )) && return 1
  echo "${UCA_MENU_STACK[$((n-1))]}"
}

menu_push() { UCA_MENU_STACK+=("$1"); }
menu_pop()  { local n=${#UCA_MENU_STACK[@]}; (( n>0 )) && unset 'UCA_MENU_STACK[$((n-1))]'; }
menu_clear(){ UCA_MENU_STACK=(); }

# Generic menu loop helper. The caller supplies a render function and a handler.
# render_fn prints the menu. handler_fn reads choice and returns one of: stay|back|exit
menu_loop() {
  local title="$1"; local render_fn="$2"; local handler_fn="$3"
  menu_push "$title"
  while true; do
    clear 2>/dev/null || true
    print_header "$title"
    "$render_fn" || true
    printf "\n${YELLOW}Select option (b=back, q=quit): ${NC}"
    local choice; read -r choice
    case "$choice" in
      b|B|back) menu_pop; return 0 ;;
      q|Q|quit) menu_clear; exit 0 ;;
      *) ;;
    esac
    local action; action=$("$handler_fn" "$choice")
    case "$action" in
      back) menu_pop; return 0 ;;
      exit) menu_clear; exit 0 ;;
      stay|*) : ;;
    esac
  done
}
