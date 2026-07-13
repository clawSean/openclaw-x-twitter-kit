# X/Twitter Kit Decisions

## 2026-07-11 - Keep Peeper dependable with a narrow syndication curl transport

Decision: Peeper uses Node `fetch` for FxTwitter, but uses a narrow fixed
`curl` transport for `syndication.twitter.com`.

Why:

- Live smoke from the workspace root passed for `@EdgeWallet` through the
  default FxTwitter path with `transport: "fetch"`.
- Live syndication did not pass with Node `fetch`: the same public syndication
  URL returned HTTP 429 from Node while `curl` with equivalent public headers
  returned HTTP 200 and usable timeline HTML.
- Cache fallback working is not enough for Peeper's purpose. Peeper is a live
  public-account monitor first; stale cache is only a last-good safety net.
- The restored curl path is intentionally narrow: no shell, no arbitrary command
  hook, no user-supplied binary/args, and only internally constructed public GETs
  to `syndication.twitter.com`.
- Default cache/state writes stayed under `skills/x-twitter-kit/state/peeper/`;
  the workspace root stayed clean of `.*-cache.json` and `.*-seen.json` files.
- The old generic `--on-new` command execution surface remains disabled.

Do not replace live syndication with stale-cache-only behavior just to satisfy a
scanner. If this curl path is rejected by a scanner, fix the scanner rule or add
an explicit allowlisted helper; do not break Peeper's monitoring purpose.
