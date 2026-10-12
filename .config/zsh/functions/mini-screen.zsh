# Screen Sharing into mini over ssh (work: via ssh.jgoon.com + Cloudflare
# Access; tailnet macs: directly). Forwards mini's :5900 to localhost:5901,
# opens Screen Sharing, and closes the forward when Screen Sharing quits
# (Cmd-Q — closing the window leaves the app running). Ctrl-C also cleans up.
# usage: mini-screen
mini-screen() {
  setopt local_options local_traps
  local port=5901 pid i up=0

  if [[ "$(uname)" != "Darwin" ]]; then
    echo "mini-screen: macOS only (Screen Sharing.app)" >&2
    return 1
  fi
  if /usr/sbin/lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
    echo "mini-screen: localhost:$port is already in use — an old forward? (pkill -f 'ssh mini-vnc')" >&2
    return 1
  fi

  ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L "${port}:localhost:5900" mini &!
  pid=$!
  # pid baked in now: the EXIT trap runs after this function's locals are gone
  trap "kill $pid 2>/dev/null" EXIT
  trap 'return 130' INT

  # wait for the forward — the first connect can sit on the Cloudflare
  # browser login + Touch ID, so allow a couple of minutes
  for i in {1..240}; do
    if /usr/sbin/lsof -nP -a -p $pid -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
      up=1
      break
    fi
    if ! kill -0 $pid 2>/dev/null; then
      echo "mini-screen: ssh exited before the forward came up (try: ssh mini 'echo ok')" >&2
      return 1
    fi
    sleep 0.5
  done
  if (( ! up )); then
    echo "mini-screen: timed out waiting for the forward" >&2
    return 1
  fi

  open -W "vnc://localhost:$port" # -W: block until Screen Sharing quits
}
