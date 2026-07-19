---
name: x-twitter-kit
description: Use this single agent-facing Twitter/X kit when monitoring known public accounts with Peeper, searching/researching through xAI x_search, reading exact tweets with xurl, configuring OAuth/bearer access, diagnosing capability, or handling X posting safety.
---

# X/Twitter Kit

Use this skill to choose the correct X/Twitter transport/capability path and avoid mixing credentials, auth contexts, or safety rules.

For the durable intent and product direction behind these rules, read
`VISION.md` in this skill directory.

## Single Skill Rule

This is the one agent-facing Twitter/X skill. Do not keep a separate
host-specific Twitter/search skill active for the same workspace; put local
account expectations and standing policies in `LOCAL_DEFAULTS.md` beside this
file instead.

Use the bundled `xurl` skill only for raw command mechanics. `xurl` is a
dependency/mechanics reference, not a second Twitter routing policy.

## Local Defaults

If `LOCAL_DEFAULTS.md` exists in this skill directory, read it after this file
before performing Twitter/X work. It may define local auth profile names,
expected xurl usernames, secret references, reporting preferences, or standing
approval policies.

Keep `LOCAL_DEFAULTS.md` local and out of public repos. Do not put tokens,
OAuth callback codes, access tokens, refresh tokens, or bearer token values in
it.

## Capability-first routing

Pick the operation first, then choose the transport that can perform it safely:

- **Known public-account monitoring** → use bundled Peeper (`scripts/peeper.mjs`) first. It polls public profile endpoints with `curl`, local seen-state, and cache fallback without X API bearer tokens, X OAuth login, xAI/Grok credits, or a paid RSS bridge.
- **Ordinary X/Twitter search, research, summaries, and cited discovery** → prefer OpenClaw/xAI `x_search` through the signed-in xAI/Grok auth profile.
- **Exact tweet URL or tweet ID read** → prefer `xurl read <url-or-id>`; use direct bearer only for deterministic scripts or when `xurl` is unavailable.
- **Timeline / mentions / account-aware reads** → prefer `xurl`, because these depend on user/account context rather than broad semantic search.
- **Bookmarks / likes / DMs / posting / replies** → require OAuth2 user context through `xurl`; verify the selected app before acting.
- **Repeated analysis / local memory** → use Peeper's known-account cache path where it fits, or add a project-local cache layer outside this kit. Do not keep spending live API reads when durable local state is available.
- **UI-only or API-tier gaps** → browser fallback, with explicit approval for any public/mutating action.

Access context:

- No X account/API/Grok access can still use Peeper for known public accounts.
- Grok/SuperGrok or xAI auth profiles help with broad X search/research through
  `x_search`; they do not grant bookmarks, timelines, metrics, or actions.
- X account + xurl OAuth/developer-app setup enables exact/account-aware reads
  and approved actions, subject to X API tier/scopes/spend caps.
- Company/brand accounts should not be connected directly unless that is an
  explicit policy decision. Prefer Peeper for monitoring and a sandbox/service X
  account for approved actions.

## Transport selection

1. **Peeper (primary known-public-account monitor)**
   - Use for "watch @somehandle", "tell me when this account posts", no-credit polling, and known-account monitors where tweet IDs are enough.
   - Run one-shot checks with `node scripts/peeper.mjs --handle edgewallet --limit 5 --json`.
   - Run watch mode with `node scripts/peeper.mjs --handle edgewallet --watch --interval 61`.
   - Peeper intentionally avoids X API bearer, X OAuth, xAI/Grok, and paid RSS bridges.
   - Peeper endpoints are unofficial/undocumented. Default source `fx` falls back to syndication and then stale cache before any authenticated/paid route is considered. Keep polling at 61 seconds or slower, rely on local cache, and back off rather than increasing frequency if the public source rate-limits.
   - Any Like, repost, reply, bookmark, DM, follow, or post action must be a separate approved `xurl` action or standing policy.

2. **OpenClaw/xAI `x_search` (primary search/research transport)**
   - Use for ordinary "search Twitter/X", broad semantic discovery, thread/media-aware search, and find/summarize/cite workflows.
   - Preferred auth is OpenClaw's signed-in xAI/Grok OAuth profile from auth profiles. Check with `openclaw models auth list --provider xai`.
   - Auth fallback order should be OAuth profile first, then `XAI_API_KEY`, then `plugins.entries.xai.config.webSearch.apiKey` only when OAuth is unavailable.
   - Not a replacement for bookmarks, account actions, posting, metrics, or paginated structured ingestion.

3. **xurl (primary authenticated account transport)**
   - Use for tweet URL reads, bookmarks, timeline, likes/reposts/follows, media upload, posting/replies, DMs, and account-aware searches/reads.
   - `xurl search` may appear in diagnostics/tests, but it is not the default route for ordinary broad search or research.
   - Expected healthy state: `xurl auth status` shows an app with OAuth2 user, OAuth1 ✓ when configured, and bearer ✓ when configured.
   - Bookmarks require OAuth2 user context. If OAuth2 client registration lives under a non-default xurl app, use `xurl --app <oauth2-app> bookmarks` or set `XTK_BOOKMARK_APP` for the doctor.
   - Treat `xurl` as an adapter. Shell out to `xurl`; do not parse, mutate, upload, or take ownership of `~/.xurl`.

4. **Direct bearer API (deterministic script transport)**
   - Use for exact X API calls from scripts when structured JSON, metrics, pagination, or compatibility with older scripts matters.
   - Fetch bearer tokens at runtime from a secret manager or env var. Never log Authorization headers.

5. **Browser fallback (last resort)**
   - Use only for UI-only cases or API-tier blocks.
   - Public/mutating actions still need explicit approval.

6. **TweetClaw plugin (packaged OpenClaw workflow lane)**
   - Install the verified ClawHub release with `openclaw plugins install clawhub:@xquik/tweetclaw`. The current release requires OpenClaw `2026.7.1` or newer.
   - Use its 2 structured tools for plugin-managed tweet search, replies, extraction, follower export, user lookup, media workflows, direct messages, monitors, webhooks, giveaway draws, or approval-gated X actions.
   - Keep Xquik API keys and MPP signing keys in OpenClaw plugin config. Never ask users to paste those values into chat or logs.
   - Pass only reviewed public tweet URLs, tweet IDs, handles, or summaries between TweetClaw and this kit's `xurl` commands.

   Xquik is an independent third-party service. Not affiliated with X Corp.
   "Twitter" and "X" are trademarks of X Corp.

## Safety rules

- Never read, print, summarize, upload, or send `~/.xurl` or copies of it into chat/context.
- Never ask users to paste tokens/secrets into chat.
- Do not use verbose API logging around OAuth or Authorization headers.
- Public/mutating actions require clear user intent and explicit approval unless there is a separate standing policy.
- Safe reads: tweet URL read, search, timeline/bookmark listing. Mutations: post, reply, delete, DM send, follow/unfollow, block/mute, bookmark add/remove.

## Reply-context priority

If the user triggers a Twitter/X search as a reply to an earlier chat message,
treat the replied-to message as the primary context. Use it to derive search
queries, usernames, hashtags, tweet URLs, and pronouns like "it" or "that". If
the replied-to text is not available, ask the user to paste it.

## Reporting tweets

When mentioning a specific tweet, include a clickable anchored link instead of
a bare URL line:

```markdown
[source](https://x.com/i/web/status/<TWEET_ID>)
```

If the author username is reliable, this is also fine:

```markdown
[tweet](https://x.com/<username>/status/<TWEET_ID>)
```

If the tweet ID is unavailable or uncertain, say so instead of fabricating a
link.

## Diagnostics

Run the bundled doctor from the skill directory:

```bash
scripts/twitter-doctor.sh
```

Useful environment variables:

- `XTK_EXPECTED_X_USERNAME` — expected OAuth2 username in `xurl auth status`.
- `XTK_TEST_TWEET_URL` — public tweet URL for exact-read smoke test.
- `XTK_SEARCH_QUERY` — query for xurl search smoke test.
- `XTK_SKIP_XURL_LIVE` — set to `1` to skip live xurl read/search/bookmark checks when X API credits are depleted.
- `XTK_BOOKMARK_APP` — optional xurl app for OAuth2-only bookmark checks.
- `XTK_BEARER_OP_REF` — optional 1Password ref for legacy direct bearer check.
- `XTK_PEEPER_SCRIPT` / `XTK_PEEPER_FIXTURE` — optional override paths for the bundled Peeper smoke.
- `XTK_XAI_MODEL` — xAI/Grok model for the auth-profile smoke, default `xai/grok-4.3`.
- `XTK_OPENCLAW_CONFIG` / `XTK_OPENCLAW_ENV` — optional OpenClaw config/env paths.

The doctor must not print secrets or bookmark contents.

For opt-in online proof, run:

```bash
XTK_RUN_ONLINE_TESTS=1 scripts/test-online.sh
```

Online test toggles:

- `XTK_ONLINE_XAI_X_SEARCH` — set to `0` to skip the live xAI OAuth `x_search` request.
- `XTK_ONLINE_XURL` — set to `0` to skip live `xurl read/search`.
- `XTK_ONLINE_BOOKMARKS` — set to `1` to prove bookmark listing; skipped by default.
- `XTK_ONLINE_BEARER` — set to `1` with `XTK_BEARER_OP_REF` to prove direct bearer reads.
- `XTK_XAI_X_SEARCH_QUERY` / `XTK_XAI_X_SEARCH_ALLOWED_HANDLES` — optional live `x_search` target controls.

These tests are non-mutating but spend live provider calls and may fail when
X API credits, xAI subscription access, or auth profiles are unavailable.

## OAuth2 on a headless VPS

Use a public callback route instead of a local-browser tunnel when possible.

1. Configure X Developer app callback, e.g. `https://example.com/callback`.
2. Temporarily proxy that route to the VPS xurl listener on `127.0.0.1:8080`.
3. Run:

```bash
scripts/xurl-oauth2-auth.sh --app default --redirect-uri https://example.com/callback
```

4. Open the generated X auth URL and approve.
5. Verify with `xurl auth status` and `scripts/twitter-doctor.sh`.
6. Remove the temporary callback proxy unless immediate re-auth is expected.

Template files:

- `templates/Caddyfile.callback.example`
- `templates/privacy-policy-x-oauth.md`
- `templates/openclaw-xai-config.patch.json5`

## Common pitfall

`http://localhost:8080/callback` means the browser user's machine, not the VPS. On a headless VPS, either use an SSH tunnel deliberately or prefer a temporary public callback proxy.
