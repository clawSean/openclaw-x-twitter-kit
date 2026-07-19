# TweetClaw companion workflow

This kit stays focused on direct X/Twitter access with xAI `x_search`, `xurl`,
OAuth setup, diagnostics, and local smoke tests. Use
[TweetClaw](https://github.com/Xquik-dev/tweetclaw) as a companion when an
OpenClaw user wants a packaged plugin path for structured X/Twitter workflows
through Xquik.

Xquik is an independent third-party service. Not affiliated with X Corp.
"Twitter" and "X" are trademarks of X Corp.

## When to use each tool

| Need | Prefer |
| --- | --- |
| Broad X/Twitter research, cited discovery, and summaries through the signed-in xAI/Grok auth profile | X/Twitter Kit |
| Configure X Developer app credentials, OAuth2 callback routing, bookmarks, and `xurl auth status` checks | X/Twitter Kit |
| Verify local `xurl`, direct bearer, or xAI setup with `twitter-doctor.sh` | X/Twitter Kit |
| Structured OpenClaw workflows for tweet search, replies, extraction, follower export, user lookup, media, direct messages, monitors, webhooks, giveaway draws, or approval-gated actions | TweetClaw |
| Move reviewed public tweet URLs or tweet IDs into a direct `xurl` check | Either tool, with reviewed public IDs only |

## Install TweetClaw beside this kit

Install the plugin through OpenClaw:

```bash
openclaw plugins install clawhub:@xquik/tweetclaw
```

The current TweetClaw release requires OpenClaw `2026.7.1` or newer. Use
`openclaw plugins install npm:@xquik/tweetclaw` only when you need the npm
fallback instead of the verified ClawHub publisher.

If the agent can read the TweetClaw skill but cannot call its tools, keep the
normal tool profile and opt into the 2 TweetClaw tool names:

```bash
openclaw config set tools.alsoAllow '["explore", "tweetclaw"]'
```

For account-backed workflows, store the Xquik API key in local OpenClaw plugin
config. Do not paste it into prompts, docs, logs, shell history, screenshots, or
issue comments.

```bash
openclaw config set plugins.entries.tweetclaw.config.apiKey "$XQUIK_API_KEY"
```

TweetClaw also supports a read-only MPP mode for eligible reads. If you use it,
store the signing key as local plugin config and keep writes, monitors,
webhooks, direct messages, media upload, media download, and giveaway draws on
the account-backed API-key path.

```bash
openclaw config set plugins.entries.tweetclaw.config.tempoSigningKey "$MPP_SIGNING_KEY"
```

## Safe handoff pattern

1. Use this kit to verify direct `xurl` auth, bookmark access, and local X API
   smoke tests.
2. Keep xAI `x_search` as the normal broad research lane.
3. Use TweetClaw when the OpenClaw task needs structured tweet search, search
   tweet replies, monitors, webhooks, follower export, user lookup, media
   workflows, giveaway draws, or approval-gated post tweets and post tweet
   replies.
4. Pass only reviewed public tweet URLs, tweet IDs, handles, or summarized
   findings between tools.
5. Keep `~/.xurl`, Xquik API keys, MPP signing keys, OAuth callback codes, and
   access or refresh tokens out of chat context and PR text.
6. Require explicit approval before any public or mutating X/Twitter action,
   including posts, replies, direct messages, follows, likes, reposts, bookmark
   changes, media upload, webhook creation, and giveaway draw publication.

## Example prompt

```text
Use x-twitter-kit to confirm my xurl app is healthy. Then use TweetClaw to
search tweets and search tweet replies for the campaign keyword, summarize the
top public URLs, and ask before posting any reply.
```
