#!/usr/bin/env bash
set -euo pipefail

APP="default"
REDIRECT_URI=""
CAPTURE_FILE=""

usage() {
  cat <<'EOF'
Usage: xurl-oauth2-auth.sh --redirect-uri URL [--app NAME] [--capture-file PATH]

Starts `xurl auth oauth2` for a headless VPS and captures the generated X auth URL
without requiring a local GUI browser.

Prereqs:
  - xurl is installed
  - app credentials were registered in xurl outside chat/agent context
  - X Developer Portal callback URL exactly matches --redirect-uri
  - if using a public callback, proxy that path to 127.0.0.1:8080 while this runs

Example:
  ./xurl-oauth2-auth.sh --app default --redirect-uri https://example.com/callback
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?missing app}"; shift 2 ;;
    --redirect-uri|--callback-url) REDIRECT_URI="${2:?missing redirect URI}"; shift 2 ;;
    --capture-file) CAPTURE_FILE="${2:?missing capture file}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$REDIRECT_URI" ]; then
  echo "Missing --redirect-uri" >&2
  usage >&2
  exit 2
fi

command -v xurl >/dev/null 2>&1 || { echo "xurl not found" >&2; exit 1; }

TMPDIR="$(mktemp -d)"
CAPTURE_FILE="${CAPTURE_FILE:-$TMPDIR/auth-url.txt}"
mkdir -p "$TMPDIR/bin" "$(dirname "$CAPTURE_FILE")"

cat > "$TMPDIR/bin/xdg-open" <<SH
#!/usr/bin/env sh
echo "\$1" > "$CAPTURE_FILE"
exit 0
SH
chmod +x "$TMPDIR/bin/xdg-open"

trap 'rm -rf "$TMPDIR"' EXIT

printf 'Starting xurl OAuth2 listener for app %s\n' "$APP"
printf 'Redirect URI: %s\n' "$REDIRECT_URI"
printf '\nIf using Caddy, temporary callback proxy example:\n'
printf '  handle /callback* {\n    reverse_proxy 127.0.0.1:8080\n  }\n\n'

PATH="$TMPDIR/bin:$PATH" REDIRECT_URI="$REDIRECT_URI" xurl --app "$APP" auth oauth2 &
PID=$!

for _ in $(seq 1 50); do
  if [ -s "$CAPTURE_FILE" ]; then
    printf '\nOpen this URL in your browser and approve access:\n\n'
    cat "$CAPTURE_FILE"
    printf '\n\nWaiting for OAuth callback...\n'
    wait "$PID"
    exit $?
  fi
  sleep 0.1
done

echo "Timed out waiting for xurl to emit auth URL" >&2
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
exit 1
