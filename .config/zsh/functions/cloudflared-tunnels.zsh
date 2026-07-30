# cloudflared tunnel helpers
# usage: sure-tunnel {on|off|restart|status|logs}
#        t3code-tunnel {on|off|restart|status|logs}
#        webhooks-tunnel {on|off|restart|status|logs}
_cf_tunnel() {
  local name="$1" action="$2"
  local label="com.jgoon.cloudflared.${name}"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"
  local svc="gui/$(id -u)/${label}"

  if [[ ! -f "$plist" && "$action" != "status" ]]; then
    echo "${name}: missing $plist" >&2
    return 1
  fi

  case "$action" in
    on)      launchctl enable "$svc"; launchctl bootstrap "gui/$(id -u)" "$plist" ;;
    off)     launchctl disable "$svc"; launchctl bootout "$svc" 2>/dev/null ;;
    restart) launchctl kickstart -k "$svc" ;;
    status)  launchctl print "$svc" 2>/dev/null | grep -E 'state|pid |last exit' || echo "${name}: not loaded" ;;
    logs)    tail -f "$HOME/Library/Logs/cloudflared-${name}.err.log" ;;
    *)       echo "usage: ${name}-tunnel {on|off|restart|status|logs}" >&2; return 1 ;;
  esac
}
sure-tunnel()     { _cf_tunnel sure "$@"; }
t3code-tunnel()   { _cf_tunnel t3code "$@"; }
webhooks-tunnel() { _cf_tunnel webhooks "$@"; }
