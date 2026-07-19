# X/Twitter Kit

[![CI](https://github.com/clawSean/openclaw-x-twitter-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/clawSean/openclaw-x-twitter-kit/actions/workflows/ci.yml)

A small OpenClaw-first helper skill + scripts for dependable X/Twitter access using layered transports and capability checks:

1. **Peeper** — no-credit public-account watcher for known handles, included in this kit and also published as a standalone repo.
2. **OpenClaw xAI `x_search`** — preferred X search/research transport, using signed-in Grok/xAI OAuth auth profiles when available.
3. **xurl** — primary authenticated X account transport for tweet reads, bookmarks, timeline, media, and user actions.
4. **Direct bearer API** — deterministic script/API transport for exact X API calls, metrics, pagination, and compatibility scripts.
5. **Browser fallback** — last resort for UI-only cases or API-tier blocks.

The kit is designed to be shareable: it ships no secrets and should work for any OpenClaw/VPS user who brings their own X Developer app and credentials.

## Who this is for

- OpenClaw operators who want X/Twitter read/search/bookmark capability.
- Agent builders who need a repeatable OAuth2/xurl setup path.
- Teams that want to monitor known public X accounts without giving an agent access to the real brand account.
- Technical friends who can bring their own X Developer app, callback URL, and credentials.

This is a **technical v0 kit**, not a hosted service or one-click consumer installer.

## Which job are you doing?

- **Watch known public accounts** → use Peeper first. It polls public profile
  endpoints with `curl`, local state, and cache fallback. It does not use X API
  bearer tokens, X OAuth login, xAI/Grok credits, or a paid RSS bridge.
- **Search/research X broadly** → use OpenClaw/xAI `x_search` through the
  signed-in Grok/xAI OAuth profile when available.
- **Read exact tweets, timelines, bookmarks, or account-aware surfaces** → use
  `xurl` with the right OAuth context.
- **Like, repost, reply, bookmark, DM, follow, or post** → use `xurl` only after
  explicit approval or a separate standing policy.
- **Company/brand account without direct agent access** → monitor with Peeper;
  use a sandbox/service X account only for approved actions.

## Access map

- **No X account, no X API, no Grok/xAI** → Peeper can still monitor known
  public accounts.
- **Grok/SuperGrok or xAI auth profile** → `x_search` can handle broad X
  research/search, but not bookmarks, account timelines, metrics, or actions.
- **X account plus xurl OAuth/developer app** → exact tweet reads,
  account-aware reads, bookmarks, media, and approved actions become possible,
  subject to X API tier, scopes, and spend caps.
- **Company/brand account that should not be exposed to the agent** → do not
  connect the real account. Use Peeper for monitoring and a sandbox/service X
  account only for explicitly approved actions.

## Design stance

- Route by **capability** first: exact tweet read, search, bookmarks, DMs, posting, media, or broad discovery may require different auth contexts.
- Monitor known public accounts with Peeper before spending X API or xAI calls.
- For ordinary "search Twitter/X", research, summaries, and cited discovery, prefer OpenClaw/xAI `x_search` through the signed-in xAI/Grok auth profile. Do not spend X API credits or reach for an xAI API-key fallback unless OAuth is unavailable.
- Treat `xurl` as an external credential adapter. This kit shells out to `xurl`; it does **not** parse, mutate, upload, or own `~/.xurl`.
- Keep durable Twitter memory/cache layers explicit. Peeper provides the bundled known-account cache path; larger analysis memory should still live in your own project state.
- Keep public/mutating actions approval-gated even when auth is healthy.

## Skill model

This repo owns the single agent-facing Twitter/X skill plus the portable setup,
diagnostics, templates, and test matrix.

In a running OpenClaw workspace, keep responsibilities split:

- `x-twitter-kit` owns agent intent routing, setup, diagnostics, and proof.
- The bundled `xurl` skill owns raw `xurl` command mechanics only.
- Optional host-specific account names, secret refs, and standing policies live
  in a local untracked `LOCAL_DEFAULTS.md` beside the installed skill.

Do not keep a separate host-specific Twitter/search skill active for the same
workspace. Do not copy host-specific secrets, profile names, or one-off account
assumptions into this public kit.

## Contents

```text
skills/x-twitter-kit/
├── SKILL.md
├── VISION.md
├── fixtures/
│   └── edgewallet-cache.json
├── scripts/
│   ├── peeper.mjs
│   ├── twitter-doctor.sh
│   └── xurl-oauth2-auth.sh
└── templates/
    ├── Caddyfile.callback.example
    ├── LOCAL_DEFAULTS.example.md
    ├── openclaw-xai-config.patch.json5
    └── privacy-policy-x-oauth.md
```

Additional docs:

- [OpenClaw install notes](docs/openclaw-install.md)
- [Local routing guide](docs/local-routing-guide.md)
- [X OAuth setup notes](docs/oauth.md)
- [TweetClaw companion workflow](docs/tweetclaw-companion.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Quick start

1. Run Peeper for no-credit known-account monitoring:

   ```bash
   node skills/x-twitter-kit/scripts/peeper.mjs --handle edgewallet --limit 5
   ```

   Watch mode uses local seen-state and only emits newly observed tweets after
   the first seed run:

   ```bash
   node skills/x-twitter-kit/scripts/peeper.mjs --handle edgewallet --watch --interval 61
   ```

2. Install `xurl` if you need authenticated account reads or actions:

   ```bash
   npm install -g @xdevplatform/xurl
   ```

3. Create/configure an X Developer app:

   - App type: **Web App / Automated App / Bot**
   - Permissions: **Read + Write + DM** if you need bookmarks, posting, and DMs
   - Callback URL: your public callback route, e.g. `https://example.com/callback`
   - Privacy/terms pages: use the templates in `skills/x-twitter-kit/templates/`

4. Register app credentials with `xurl` outside of agent/chat context. Do not paste credentials into chat or commit them.

5. Sign into xAI/Grok in OpenClaw for OAuth-backed `x_search`:

   ```bash
   openclaw models auth login --provider xai --method oauth
   openclaw models auth list --provider xai
   ```

   On a headless/VPS setup, use device-code auth when available:

   ```bash
   openclaw models auth login --provider xai --device-code
   ```

6. Run OAuth2 auth for X account surfaces:

   ```bash
   skills/x-twitter-kit/scripts/xurl-oauth2-auth.sh \
     --app default \
     --redirect-uri https://example.com/callback
   ```

7. Run the doctor:

   ```bash
   XTK_EXPECTED_X_USERNAME=your_handle \
   XTK_BOOKMARK_APP=default \
   skills/x-twitter-kit/scripts/twitter-doctor.sh
   ```

   If your OAuth2 client registration is in a separate xurl app, set `XTK_BOOKMARK_APP` to that app name.

8. Install the skill into OpenClaw:

   ```bash
   cp -R skills/x-twitter-kit ~/.openclaw/workspace/skills/
   ```

   Or configure `skills.load.extraDirs` to point at this repo's `skills` directory. See [OpenClaw install notes](docs/openclaw-install.md).

9. Optional: add local host defaults:

   ```bash
   cp skills/x-twitter-kit/templates/LOCAL_DEFAULTS.example.md \
     ~/.openclaw/workspace/skills/x-twitter-kit/LOCAL_DEFAULTS.md
   ```

   Edit the local copy with your expected auth profile names, xurl username,
   secret refs, and standing policies. Do not commit secrets or token values.

## Safety model

- Peeper is for discovering public tweet IDs from known public accounts. It
  uses unofficial public endpoints, local cache fallback, and no X/xAI auth.
  Treat it as a practical monitor, not a permanent platform contract.
- Peeper's default public-source path tries FxTwitter first, falls back to
  syndication, and then falls back to stale local cache before failing.
- Bookmarks require OAuth2 user context. OAuth1 and app-only bearer are not enough.
- Some xurl setups keep OAuth2 client registration and default OAuth1/bearer credentials under different app names. That is okay; use `XTK_BOOKMARK_APP` / `xurl --app <oauth2-app>` for OAuth2-only endpoints.
- `x_search` should be the default for broad discovery and research, and it should prefer OpenClaw's xAI OAuth auth profile. It is not a replacement for bookmarks, posting, metrics, pagination, or other structured/account actions.
- If both xAI OAuth and `XAI_API_KEY` are configured, treat the API key as a fallback, not the normal Twitter-search lane.
- Public/mutating actions — posting, replies, DMs, likes/reposts, follows, bookmark mutation, deletes — should stay approval-gated.
- Never commit or paste `~/.xurl`, OAuth callback codes, client secrets, access/refresh tokens, bearer tokens, or xAI keys.

## Local validation

```bash
scripts/ci-check.sh
```

`ci-check.sh` includes `scripts/test.sh`, an offline fake-command capability
matrix for the doctor. It exercises:

- Peeper no-credit monitoring, proving no auth, X API, or xAI path is used.
- xAI/Grok OAuth auth-profile primary routing.
- Expired/stale OAuth profile refresh smoke behavior.
- `XAI_API_KEY` fallback behavior when OAuth is absent.
- `xurl` exact read, search, and bookmark checks.
- Direct bearer fallback checks without printing bearer values.
- Expected-user mismatch failure behavior.
- Malformed xAI auth JSON.
- Missing and partial OpenClaw config surfaces.
- xurl live read failures.
- Direct bearer HTTP failures.
- API-key fallback secret-leak canaries.
- Guardrails that validation does not call mutating xurl verbs such as post,
  reply, like, repost, delete, follow, DM, mute, or block.

## Optional online validation

The online runner is opt-in because it spends live xAI/X calls and can fail
when credentials, subscriptions, or X API credits are unavailable:

```bash
XTK_RUN_ONLINE_TESTS=1 scripts/test-online.sh
```

By default it runs only non-mutating checks:

- xAI/Grok auth-profile model smoke, then a direct xAI Responses `x_search`
  request using the OpenClaw xAI OAuth profile.
- `xurl read` against `XTK_TEST_TWEET_URL`.
- `xurl search` against `XTK_SEARCH_QUERY`.

Additional online checks are explicit:

```bash
XTK_RUN_ONLINE_TESTS=1 \
XTK_ONLINE_BOOKMARKS=1 \
XTK_BOOKMARK_APP=default \
scripts/test-online.sh
```

```bash
XTK_RUN_ONLINE_TESTS=1 \
XTK_ONLINE_BEARER=1 \
XTK_BEARER_OP_REF='op://Vault/Item/Bearer Token' \
scripts/test-online.sh
```

The online runner never calls posting, reply, like, repost, delete, follow,
bookmark-mutation, DM, mute, or block commands. Bookmark list checks store
temporary JSON only long enough to validate shape and do not print bookmark
contents.

For live auth validation, run the doctor with your own credentials/config:

```bash
XTK_EXPECTED_X_USERNAME=your_handle \
XTK_BOOKMARK_APP=default \
skills/x-twitter-kit/scripts/twitter-doctor.sh
```
