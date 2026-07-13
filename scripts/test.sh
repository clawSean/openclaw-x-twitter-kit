#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/skills/x-twitter-kit/scripts/twitter-doctor.sh"
REAL_PATH="$PATH"

TESTS_RUN=0

pass() {
  printf 'ok %s\n' "$1"
}

fail() {
  printf 'not ok %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" >&2
  fi
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
    pass "$label"
  else
    fail "$label" "Expected to find: $needle"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "$needle" "$file"; then
    fail "$label" "Unexpected content found: $needle"
  else
    pass "$label"
  fi
}

write_config() {
  local dir="$1"
  cat >"$dir/openclaw.json" <<'JSON'
{
  "skills": {
    "entries": {
      "xurl": { "enabled": true }
    }
  },
  "plugins": {
    "entries": {
      "xai": {
        "enabled": true,
        "config": {
          "xSearch": { "enabled": true }
        }
      }
    }
  },
  "tools": {
    "alsoAllow": ["x_search"]
  }
}
JSON
  : >"$dir/openclaw.env"
}

write_fake_openclaw() {
  local bin="$1"
  cat >"$bin/openclaw" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'openclaw %s\n' "$*" >>"${XTK_TEST_CALL_LOG:?}"

if [ "${1:-}" = "models" ] && [ "${2:-}" = "auth" ] && [ "${3:-}" = "list" ]; then
  case "${XTK_TEST_XAI_AUTH:-ok}" in
    ok)
      printf '{"profiles":[{"id":"xai:jaredpearson@outlook.com","provider":"xai","type":"oauth","expiresAt":"2999-01-01T00:00:00Z"}]}\n'
      ;;
    expired)
      printf '{"profiles":[{"id":"xai:jaredpearson@outlook.com","provider":"xai","type":"oauth","expiresAt":"2000-01-01T00:00:00Z"}]}\n'
      ;;
    missing)
      printf '{"profiles":[]}\n'
      ;;
    malformed)
      printf '{not-json}\n'
      ;;
    *)
      printf 'unknown auth fixture\n' >&2
      exit 2
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "infer" ] && [ "${2:-}" = "model" ] && [ "${3:-}" = "run" ]; then
  if [ "${XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY:-0}" = "1" ] && [ -n "${XAI_API_KEY:-}" ]; then
    printf 'expected XAI_API_KEY to be empty for auth-profile smoke\n' >&2
    exit 9
  fi
  if [ "${XTK_TEST_REQUIRE_PRESENT_XAI_API_KEY:-0}" = "1" ] && [ -z "${XAI_API_KEY:-}" ]; then
    printf 'expected XAI_API_KEY to be present for fallback smoke\n' >&2
    exit 10
  fi
  printf '{"ok":true,"outputs":[{"text":"%s"}]}\n' "${XTK_XAI_EXPECTED:-XTK_XAI_OAUTH_OK}"
  exit 0
fi

printf 'unexpected openclaw command: %s\n' "$*" >&2
exit 2
SH
  chmod +x "$bin/openclaw"
}

write_fake_xurl() {
  local bin="$1"
  cat >"$bin/xurl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'xurl %s\n' "$*" >>"${XTK_TEST_CALL_LOG:?}"

for arg in "$@"; do
  case "$arg" in
    post|reply|like|repost|delete|follow|unfollow|dm|mute|block)
      printf 'mutating xurl command blocked in test: %s\n' "$arg" >&2
      exit 42
      ;;
  esac
done

if [ "${1:-}" = "--app" ]; then
  shift 2
fi

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  printf 'default\n'
  printf 'oauth2: %s\n' "${XTK_TEST_XURL_USER:-dasPoppers}"
  printf 'oauth1: ✓\n'
  printf 'bearer: ✓\n'
  exit 0
fi

case "${1:-}" in
  read)
    if [ "${XTK_TEST_FAIL_XURL_READ:-0}" = "1" ]; then
      printf 'rate limit exceeded\n' >&2
      exit 88
    fi
    printf '{"data":{"id":"2056872329561710766"}}\n'
    ;;
  search)
    if [ "${XTK_TEST_FAIL_XURL_SEARCH:-0}" = "1" ]; then
      printf 'search backend unavailable\n' >&2
      exit 88
    fi
    printf '{"data":[{"id":"2056872329561710766"}]}\n'
    ;;
  bookmarks)
    printf '{"data":[{"id":"bookmark-1"}]}\n'
    ;;
  *)
    printf 'unexpected xurl command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$bin/xurl"
}

write_fake_op() {
  local bin="$1"
  cat >"$bin/op" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'op %s\n' "$*" >>"${XTK_TEST_CALL_LOG:?}"

if [ "${1:-}" = "read" ]; then
  printf 'fake-bearer-token\n'
  exit 0
fi

printf 'unexpected op command: %s\n' "$*" >&2
exit 2
SH
  chmod +x "$bin/op"
}

write_fake_curl() {
  local bin="$1"
  cat >"$bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'curl called\n' >>"${XTK_TEST_CALL_LOG:?}"

out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w|-H)
      shift 2
      ;;
    -sS|-L)
      shift
      ;;
    --max-time|-A)
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

if [ -z "$out" ]; then
  if [[ "$url" == *"api.fxtwitter.com"* ]] && [ "${XTK_TEST_FAIL_FX:-0}" = "1" ]; then
    printf '\n__HTTP_STATUS__:500\n'
    exit 0
  fi
  if [[ "$url" == *"syndication.twitter.com"* ]]; then
    cat <<'HTML'
<html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"timeline":{"entries":[{"type":"tweet","content":{"tweet":{"id_str":"2063297533732962729","created_at":"2026-06-06T16:30:40.000Z","full_text":"EdgeWallet syndication fallback post"}}}]}}}}</script></html>
HTML
    printf '\n__PEEPER_CURL_HTTP_STATUS__200\n'
    exit 0
  fi
  if [ "${XTK_TEST_CURL_HTTP_CODE:-200}" = "200" ]; then
    cat <<'JSON'
{"results":[{"type":"status","id":"2063297533732962729","created_at":"2026-06-06T16:30:40.000Z","raw_text":{"text":"EdgeWallet test post"},"author":{"screen_name":"edgewallet"},"url":"https://x.com/EdgeWallet/status/2063297533732962729"}]}
JSON
  fi
  printf '\n__HTTP_STATUS__:%s\n' "${XTK_TEST_CURL_HTTP_CODE:-200}"
  exit 0
fi

printf '{"data":{"id":"2056872329561710766"}}\n' >"$out"
printf '%s' "${XTK_TEST_CURL_HTTP_CODE:-200}"
SH
  chmod +x "$bin/curl"
}

write_partial_config() {
  local dir="$1"
  cat >"$dir/openclaw.json" <<'JSON'
{
  "skills": {
    "entries": {
      "xurl": { "enabled": true }
    }
  },
  "plugins": {
    "entries": {
      "xai": {
        "enabled": false,
        "config": {
          "xSearch": { "enabled": true }
        }
      }
    }
  },
  "tools": {
    "alsoAllow": []
  }
}
JSON
}

new_case_dir() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/xtk-test.XXXXXX")"
  mkdir -p "$dir/bin"
  write_config "$dir"
  write_fake_openclaw "$dir/bin"
  write_fake_xurl "$dir/bin"
  write_fake_curl "$dir/bin"
  printf '%s\n' "$dir"
}

run_doctor() {
  local dir="$1"
  shift
  env \
    PATH="$dir/bin:$REAL_PATH" \
    XTK_OPENCLAW_CONFIG="$dir/openclaw.json" \
    XTK_OPENCLAW_ENV="$dir/openclaw.env" \
    XTK_TEST_CALL_LOG="$dir/calls.log" \
    XAI_API_KEY= \
    "$@" \
    "$DOCTOR" >"$dir/out" 2>&1
}

assert_no_mutating_xurl_calls() {
  local dir="$1"
  if grep -Eq 'xurl .*( post| reply| like| repost| delete| follow| unfollow| dm| mute| block)( |$)' "$dir/calls.log"; then
    fail "xurl mutation guard" "$(cat "$dir/calls.log")"
  fi
  pass "xurl mutation guard"
}

case_oauth_primary_skip_live() {
  local dir
  dir="$(new_case_dir)"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "xAI OAuth auth profile present" "oauth profile detected"
  assert_contains "$dir/out" "xAI API-key fallback absent; OAuth profile is configured as primary" "oauth primary without api key"
  assert_contains "$dir/out" "Peeper no-credit monitor works" "peeper no-credit smoke"
  assert_contains "$dir/out" "xAI/Grok model smoke works with auth-profile lane" "oauth model smoke"
  assert_contains "$dir/out" "Summary: 10 passed, 2 warnings, 0 failed" "oauth skip-live summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_expired_oauth_refresh_smoke() {
  local dir
  dir="$(new_case_dir)"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=expired \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "token is expired/stale; model smoke will attempt refresh" "expired oauth refresh warning"
  assert_contains "$dir/out" "xAI/Grok model smoke works with auth-profile lane" "expired oauth model smoke"
  assert_contains "$dir/out" "Summary: 9 passed, 3 warnings, 0 failed" "expired oauth summary"
  rm -rf "$dir"
}

case_api_key_fallback_without_oauth() {
  local dir
  dir="$(new_case_dir)"
  printf 'XAI_API_KEY=fallback-test-key\n' >"$dir/openclaw.env"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=missing \
    XTK_TEST_REQUIRE_PRESENT_XAI_API_KEY=1 \
    XAI_API_KEY=fallback-test-key \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "xAI OAuth auth profile missing" "missing oauth reported"
  assert_contains "$dir/out" "xAI API-key fallback appears configured (not primary)" "api fallback detected"
  assert_contains "$dir/out" "xAI/Grok model smoke works with API-key fallback lane" "api fallback smoke"
  assert_contains "$dir/out" "Summary: 9 passed, 3 warnings, 0 failed" "api fallback summary"
  rm -rf "$dir"
}

case_xurl_live_capabilities() {
  local dir
  dir="$(new_case_dir)"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_BOOKMARK_APP=jpop-oauth2
  assert_contains "$dir/out" "xurl exact tweet URL read works" "xurl read smoke"
  assert_contains "$dir/out" "xurl search works" "xurl search smoke"
  assert_contains "$dir/out" "xurl bookmarks work via app jpop-oauth2" "xurl bookmark app smoke"
  assert_contains "$dir/out" "Summary: 13 passed, 1 warnings, 0 failed" "xurl live summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_direct_bearer_success() {
  local dir
  dir="$(new_case_dir)"
  write_fake_op "$dir/bin"
  write_fake_curl "$dir/bin"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1 \
    "XTK_BEARER_OP_REF=op://Sean/Twitter API Key/Bearer Token"
  assert_contains "$dir/out" "legacy direct bearer tweet read works" "direct bearer smoke"
  assert_not_contains "$dir/out" "fake-bearer-token" "direct bearer token redacted"
  assert_contains "$dir/out" "Summary: 11 passed, 1 warnings, 0 failed" "direct bearer summary"
  rm -rf "$dir"
}

case_malformed_xai_auth_json() {
  local dir
  dir="$(new_case_dir)"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=malformed \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "xAI OAuth auth profile check inconclusive" "malformed xai auth reported inconclusive"
  assert_contains "$dir/out" "xAI/Grok model smoke skipped" "malformed xai auth skips model smoke"
  assert_contains "$dir/out" "Summary: 7 passed, 5 warnings, 0 failed" "malformed xai auth summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_missing_openclaw_config() {
  local dir
  dir="$(new_case_dir)"
  rm -f "$dir/openclaw.json"
  run_doctor "$dir" \
    XTK_OPENCLAW_CONFIG="$dir/openclaw.json" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "OpenClaw config not found" "missing config warning"
  assert_contains "$dir/out" "xAI OAuth auth profile present" "missing config still inspects xai auth"
  assert_contains "$dir/out" "Summary: 9 passed, 3 warnings, 0 failed" "missing config summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_partial_openclaw_config_surfaces() {
  local dir
  dir="$(new_case_dir)"
  write_partial_config "$dir"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "OpenClaw config is missing some X surfaces" "partial config warning"
  assert_contains "$dir/out" "NO plugins.entries.xai.enabled" "partial config reports xai disabled"
  assert_contains "$dir/out" "Summary: 9 passed, 3 warnings, 0 failed" "partial config summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_xurl_live_read_failure() {
  local dir status
  dir="$(new_case_dir)"
  status=0
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_TEST_FAIL_XURL_READ=1 || status=$?
  if [ "$status" -eq 0 ]; then
    fail "xurl live read failure exits nonzero" "$(cat "$dir/out")"
  fi
  pass "xurl live read failure exits nonzero"
  assert_contains "$dir/out" "xurl exact tweet read failed" "xurl read failure reported"
  assert_contains "$dir/out" "xurl search works" "xurl search still smoke-passes after read failure"
  assert_contains "$dir/out" "Summary: 12 passed, 1 warnings, 1 failed" "xurl read failure summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_direct_bearer_http_failure() {
  local dir
  dir="$(new_case_dir)"
  write_fake_op "$dir/bin"
  write_fake_curl "$dir/bin"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_SKIP_XURL_LIVE=1 \
    XTK_TEST_CURL_HTTP_CODE=500 \
    "XTK_BEARER_OP_REF=op://Sean/Twitter API Key/Bearer Token"
  assert_contains "$dir/out" "legacy direct bearer tweet read failed" "bearer http failure reported"
  assert_contains "$dir/out" "HTTP 500" "bearer http failure includes status code"
  assert_not_contains "$dir/out" "fake-bearer-token" "bearer http failure does not leak token"
  assert_contains "$dir/out" "Summary: 10 passed, 2 warnings, 0 failed" "bearer http failure summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_api_key_fallback_does_not_leak_secret() {
  local dir canary
  dir="$(new_case_dir)"
  canary="LEAK-CANARY-7e3f9c1a-do-not-print"
  printf 'XAI_API_KEY=%s\n' "$canary" >"$dir/openclaw.env"
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=missing \
    XTK_TEST_REQUIRE_PRESENT_XAI_API_KEY=1 \
    XAI_API_KEY="$canary" \
    XTK_SKIP_XURL_LIVE=1
  assert_contains "$dir/out" "xAI API-key fallback appears configured (not primary)" "fallback detected for leak guard"
  assert_contains "$dir/out" "xAI/Grok model smoke works with API-key fallback lane" "fallback smoke runs for leak guard"
  assert_not_contains "$dir/out" "$canary" "api-key fallback does not leak secret value"
  assert_contains "$dir/out" "Summary: 9 passed, 3 warnings, 0 failed" "fallback leak-guard summary"
  assert_no_mutating_xurl_calls "$dir"
  rm -rf "$dir"
}

case_expected_user_mismatch_fails() {
  local dir status
  dir="$(new_case_dir)"
  status=0
  run_doctor "$dir" \
    XTK_TEST_XAI_AUTH=ok \
    XTK_TEST_REQUIRE_EMPTY_XAI_API_KEY=1 \
    XTK_EXPECTED_X_USERNAME=wrongUser \
    XTK_SKIP_XURL_LIVE=1 || status=$?
  if [ "$status" -eq 0 ]; then
    fail "expected username mismatch exits nonzero" "$(cat "$dir/out")"
  fi
  pass "expected username mismatch exits nonzero"
  assert_contains "$dir/out" "xurl OAuth2 user mismatch" "expected username mismatch reported"
  rm -rf "$dir"
}

case_peeper_fx_falls_back_to_syndication() {
  local dir
  dir="$(new_case_dir)"
  env \
    PATH="$dir/bin:$REAL_PATH" \
    XTK_TEST_CALL_LOG="$dir/calls.log" \
    XTK_TEST_FAIL_FX=1 \
    node "$ROOT/skills/x-twitter-kit/scripts/peeper.mjs" \
      --handle edgewallet \
      --cache "$dir/peeper-cache.json" \
      --limit 1 \
      --json >"$dir/out" 2>&1
  assert_contains "$dir/out" '"sourceKind": "syndication"' "peeper fx fallback source kind"
  assert_contains "$dir/out" '"fallbackFrom": "fx"' "peeper records fx fallback"
  assert_contains "$dir/out" '"xApiUsed": false' "peeper fallback avoids x api"
  assert_contains "$dir/out" '"xAiUsed": false' "peeper fallback avoids xai"
  rm -rf "$dir"
}

printf '== offline doctor capability tests ==\n'
case_oauth_primary_skip_live
TESTS_RUN=$((TESTS_RUN+1))
case_expired_oauth_refresh_smoke
TESTS_RUN=$((TESTS_RUN+1))
case_api_key_fallback_without_oauth
TESTS_RUN=$((TESTS_RUN+1))
case_xurl_live_capabilities
TESTS_RUN=$((TESTS_RUN+1))
case_direct_bearer_success
TESTS_RUN=$((TESTS_RUN+1))
case_expected_user_mismatch_fails
TESTS_RUN=$((TESTS_RUN+1))
case_malformed_xai_auth_json
TESTS_RUN=$((TESTS_RUN+1))
case_missing_openclaw_config
TESTS_RUN=$((TESTS_RUN+1))
case_partial_openclaw_config_surfaces
TESTS_RUN=$((TESTS_RUN+1))
case_xurl_live_read_failure
TESTS_RUN=$((TESTS_RUN+1))
case_direct_bearer_http_failure
TESTS_RUN=$((TESTS_RUN+1))
case_api_key_fallback_does_not_leak_secret
TESTS_RUN=$((TESTS_RUN+1))
case_peeper_fx_falls_back_to_syndication
TESTS_RUN=$((TESTS_RUN+1))

printf 'PASS %d test cases\n' "$TESTS_RUN"
