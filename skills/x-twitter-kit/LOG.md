# X/Twitter Kit Log

## 2026-07-12 - Peeper transport correction artifact

Context:

- Jared called out that I had treated a stale-cache fallback as acceptable for
  Peeper, which misses the point of the tool. Peeper is supposed to be a
  dependable live public-account monitor, not a cache viewer with confidence.
- The specific bad instinct was trying to make the scanner/security story
  cleaner by removing curl from syndication polling, then accepting "cache
  fallback works" as enough when Node `fetch` hit HTTP 429.

What I changed on 2026-07-11:

- Kept the default FxTwitter path on Node `fetch`, because live smoke testing
  showed it successfully returned current `@EdgeWallet` posts.
- Restored live syndication polling through a narrow fixed `curl` transport,
  because the same public syndication URL returned HTTP 429 via Node `fetch`
  while curl returned HTTP 200 during the incident investigation.
- Did not restore the old generic command execution surface. `--on-new` remains
  disabled and only prints a warning if supplied.
- Kept the curl usage constrained to internally constructed public GETs for
  `https://syndication.twitter.com/srv/timeline-profile/screen-name/<handle>`.
  It uses `execFile`, no shell, no user-supplied binary, no user-supplied args,
  and no user-supplied host.
- Moved default Peeper state/cache paths under
  `skills/x-twitter-kit/state/peeper/` so regular runs do not litter the
  workspace root with hidden cache/state files.
- Recorded the decision in `skills/x-twitter-kit/DECISIONS.md`.

Validation:

- 2026-07-11 incident smoke:
  - FxTwitter via Node `fetch`: live, HTTP 200 path, current EdgeWallet posts.
  - Syndication via Node `fetch`: HTTP 429.
  - Syndication via curl: HTTP 200 and usable timeline HTML.
- 2026-07-12 follow-up smoke:
  - `node skills/x-twitter-kit/scripts/peeper.mjs --handle EdgeWallet --source fx --limit 1 --json`
    returned live FxTwitter data with `stale: false`, `transport: "fetch"`,
    17 tweets, latest ID `2076407489977884746`, created
    `Sun Jul 12 20:44:58 +0000 2026`.
  - `node skills/x-twitter-kit/scripts/peeper.mjs --handle EdgeWallet --source syndication --limit 1 --json`
    fell back to stale cache because syndication returned HTTP 429.
  - Direct curl status check to syndication on 2026-07-12 also returned HTTP
    429. So the correction is still directionally right, but curl is necessary,
    not magic; the public endpoint can still rate-limit.

Lessons:

- A monitoring tool must optimize for fresh signal first. Stale cache is a
  last-good safety net, not a successful poll.
- "No child process" is not automatically safer if it destroys the tool's core
  purpose. The right security boundary here is a narrow allowlisted transport,
  not deleting the only currently working transport class for a public endpoint.
- Scanner cleanliness is not the product requirement. If a scanner rejects the
  narrow curl transport, fix the scanner rule or move the transport into an
  explicit allowlisted helper; do not quietly degrade Peeper into stale-cache
  cosplay.
- Transport behavior is fingerprint-sensitive. Node `fetch` and curl can get
  materially different responses from the same public URL, even with similar
  headers.

Follow-ups:

- Consider separating default cache files by source. During the 2026-07-12
  smoke, a failed `--source syndication` run could return stale cache previously
  written by the FxTwitter source, which is usable as last-good tweet data but
  makes the reported `sourceKind`/`transport` confusing.
- If syndication 429s persist, evaluate a small allowlisted helper with better
  browser-like transport behavior, but keep the same principle: public GETs
  only, no arbitrary command hooks.
