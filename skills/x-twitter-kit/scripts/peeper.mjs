#!/usr/bin/env node

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const DEFAULT_HANDLE = "edgewallet";
const FXT_ENDPOINT_HOST = "api.fxtwitter.com";
const SYNDICATION_ENDPOINT_HOST = "syndication.twitter.com";
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PEEPER_STATE_DIR = join(SCRIPT_DIR, "..", "state", "peeper");

// Node's fetch gets HTTP 429 from syndication.twitter.com even with headers
// that curl sends successfully as HTTP 200 (TLS/HTTP2 fingerprinting on
// Twitter's side, not a credential or rate issue). This is a narrow, fixed
// transport for exactly one public GET target: no shell, no user-supplied
// binary/args/URL, curl output only.
const CURL_BIN = "curl";
const CURL_STATUS_MARKER = "__PEEPER_CURL_HTTP_STATUS__";
const PUBLIC_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36";

function parseArgs(argv) {
  const args = {
    handle: DEFAULT_HANDLE,
    source: "fx",
    limit: 10,
    json: false,
    watch: false,
    once: false,
    interval: 61,
    state: null,
    cache: null,
    onNew: "",
    includeReposts: false,
    includeReplies: false,
    emitExisting: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--handle") args.handle = argv[++i] || DEFAULT_HANDLE;
    else if (arg === "--source") args.source = argv[++i] || args.source;
    else if (arg === "--limit") args.limit = Number(argv[++i] || args.limit);
    else if (arg === "--interval") args.interval = Number(argv[++i] || args.interval);
    else if (arg === "--state") args.state = argv[++i] || args.state;
    else if (arg === "--cache") args.cache = argv[++i] || args.cache;
    else if (arg === "--on-new") args.onNew = argv[++i] || "";
    else if (arg === "--json") args.json = true;
    else if (arg === "--watch") args.watch = true;
    else if (arg === "--once") args.once = true;
    else if (arg === "--include-reposts") args.includeReposts = true;
    else if (arg === "--include-replies") args.includeReplies = true;
    else if (arg === "--emit-existing") args.emitExisting = true;
    else if (arg === "--help" || arg === "-h") {
      console.log(`Usage:
  node peeper.mjs [--handle edgewallet] [--source fx] [--limit 10] [--json]
  node peeper.mjs --watch [--interval 61] [--state .edgewallet-seen.json]
  node peeper.mjs --watch

Options:
  --handle <name>       X handle to poll. Default: edgewallet
  --source <name>       Poll source: fx or syndication. Default: fx
  --limit <n>           Tweets to show in one-shot mode. Default: 10
  --watch               Poll forever with local dedupe state
  --once                Run one watch iteration and exit, useful for smoke tests
  --interval <seconds>  Watch interval. Default: 61
  --state <path>        State file. Default: state/peeper/<handle>-seen.json under this skill
  --cache <path>        Last-good poll cache. Default: state/peeper/<handle>-cache.json under this skill
  --on-new <command>    Deprecated. Command hooks are disabled for safety
  --include-reposts     Include reposts/retweets when the source exposes them
  --include-replies     Include replies when the source exposes them
  --emit-existing       Treat existing timeline tweets as new on first run`);
      process.exit(0);
    }
  }
  if (!Number.isFinite(args.limit) || args.limit < 1) args.limit = 10;
  if (!Number.isFinite(args.interval) || args.interval < 61) args.interval = 61;
  if (!["fx", "syndication"].includes(args.source)) {
    throw new Error("--source must be fx or syndication");
  }
  args.handle = args.handle.replace(/^@/, "").trim();
  args.state ||= defaultStatePath(args.handle);
  args.cache ||= defaultCachePath(args.handle);
  return args;
}

function defaultStatePath(handle) {
  return join(DEFAULT_PEEPER_STATE_DIR, `${handle.toLowerCase()}-seen.json`);
}

function defaultCachePath(handle) {
  return join(DEFAULT_PEEPER_STATE_DIR, `${handle.toLowerCase()}-cache.json`);
}

function extractNextData(html) {
  const match = html.match(
    /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) {
    throw new Error("Could not find __NEXT_DATA__ in syndication timeline response");
  }
  return JSON.parse(match[1]);
}

function normalizeSyndicationTweet(entry, handle) {
  const tweet = entry?.content?.tweet;
  if (!tweet) return null;

  const id = tweet.id_str || String(tweet.id || "") || entry.entry_id?.replace(/^tweet-/, "");
  if (!id) return null;

  return {
    id,
    createdAt: tweet.created_at,
    text: htmlDecode(tweet.full_text || tweet.text || "").replace(/\s+/g, " ").trim(),
    url: `https://x.com/${handle}/status/${id}`,
  };
}

function normalizeFxTweet(entry, handle) {
  if (entry?.type !== "status") return null;
  const id = String(entry.id || "");
  if (!id) return null;

  return {
    id,
    createdAt: entry.created_at,
    text: String(entry.raw_text?.text || entry.text || "").replace(/\s+/g, " ").trim(),
    url: `https://x.com/${handle}/status/${id}`,
    sourceUrl: entry.url || `https://x.com/${handle}/status/${id}`,
    author: entry.author?.screen_name || "",
    isReply: Boolean(entry.replying_to),
  };
}

function htmlDecode(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

async function poll(args) {
  if (args.source === "syndication") return await pollSyndication(args.handle, args.cache);
  return await pollFx(args.handle, args.cache, {
    includeReplies: args.includeReplies,
    includeReposts: args.includeReposts,
  });
}

async function pollFx(handle, cachePath, { includeReplies, includeReposts }) {
  const url = `https://${FXT_ENDPOINT_HOST}/2/profile/${encodeURIComponent(handle)}/statuses?count=20`;
  let body;
  try {
    if (process.env.XTK_TEST_FAIL_FX === "1") {
      throw new Error("forced FxTwitter test failure");
    }
    body = await fetchPublicUrl(url);
  } catch (error) {
    return await pollFreeFallback(handle, cachePath, `FxTwitter fetch failed: ${error.message}`);
  }

  let data;
  try {
    data = JSON.parse(body);
  } catch (error) {
    return await pollFreeFallback(handle, cachePath, `FxTwitter response parse failed: ${error.message}`);
  }
  const tweets = (data.results || [])
    .map((entry) => normalizeFxTweet(entry, handle))
    .filter(Boolean)
    .filter((tweet) => includeReposts || tweet.author.toLowerCase() === handle.toLowerCase())
    .filter((tweet) => includeReplies || !tweet.isReply)
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const result = {
    source: url,
    sourceKind: "fx",
    transport: "fetch",
    authUsed: false,
    xApiUsed: false,
    xAiUsed: false,
    stale: false,
    fetchedAt: new Date().toISOString(),
    count: tweets.length,
    tweets,
  };
  saveCache(cachePath, result);
  return result;
}

async function pollFreeFallback(handle, cachePath, reason) {
  try {
    const result = await pollSyndication(handle, cachePath);
    return {
      ...result,
      fallbackFrom: "fx",
      fallbackReason: reason,
    };
  } catch (error) {
    const cached = loadCache(cachePath);
    if (!cached) throw new Error(`${reason}; syndication fallback failed: ${error.message}`);
    return {
      ...cached,
      stale: true,
      staleReason: `${reason}; syndication fallback failed: ${error.message}`,
    };
  }
}

async function pollSyndication(handle, cachePath) {
  const url = `https://${SYNDICATION_ENDPOINT_HOST}/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}`;
  let html;
  try {
    html = await fetchSyndicationUrl(url);
  } catch (error) {
    const cached = loadCache(cachePath);
    if (!cached) throw error;
    return {
      ...cached,
      stale: true,
      staleReason: error.message,
    };
  }

  let data;
  try {
    data = extractNextData(html);
  } catch (error) {
    const cached = loadCache(cachePath);
    if (!cached) throw error;
    return {
      ...cached,
      stale: true,
      staleReason: error.message,
    };
  }
  const entries = data?.props?.pageProps?.timeline?.entries || [];
  const tweets = entries
    .filter((entry) => entry?.type === "tweet")
    .map((entry) => normalizeSyndicationTweet(entry, handle))
    .filter(Boolean)
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const result = {
    source: url,
    sourceKind: "syndication",
    transport: "curl",
    authUsed: false,
    xApiUsed: false,
    xAiUsed: false,
    stale: false,
    fetchedAt: new Date().toISOString(),
    count: tweets.length,
    tweets,
  };
  saveCache(cachePath, result);
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.watch || args.once) {
    await watch(args);
    return;
  }

  const result = await poll(args);
  const shownTweets = result.tweets.slice(0, args.limit);
  const output = { ...result, tweets: shownTweets };

  if (args.json) {
    console.log(JSON.stringify(output, null, 2));
    return;
  }

  printHeader(output);
  for (const tweet of shownTweets) {
    console.log(`- ${tweet.id} | ${tweet.createdAt} | ${tweet.url}`);
    console.log(`  ${tweet.text.slice(0, 180)}`);
  }
}

async function watch(args) {
  console.log(`watching @${args.handle} every ${args.interval}s`);
  console.log(`state=${args.state}`);
  console.log(`cache=${args.cache}`);
  console.log(`onNew=${args.onNew || "(print only)"}`);

  do {
    const startedAt = new Date();
    try {
      const result = await poll(args);
      const state = loadState(args.state);
      const seen = new Set(state.seen || []);
      const firstRun = seen.size === 0;
      const newTweets = result.tweets.filter((tweet) => !seen.has(tweet.id)).reverse();

      if (result.stale) {
        console.log(`${startedAt.toISOString()} stale cache used: ${result.staleReason}`);
      }

      if (firstRun && !args.emitExisting) {
        for (const tweet of result.tweets) seen.add(tweet.id);
        saveState(args.state, seen, startedAt);
        console.log(`${startedAt.toISOString()} seeded ${seen.size} existing tweets; waiting for new posts`);
      } else if (newTweets.length === 0) {
        saveState(args.state, seen, startedAt);
        console.log(`${startedAt.toISOString()} no new tweets; latest=${result.tweets[0]?.id || "none"}`);
      } else {
        for (const tweet of newTweets) {
          console.log(`${startedAt.toISOString()} NEW ${tweet.id} ${tweet.url}`);
          console.log(tweet.text.slice(0, 220));
          if (args.onNew) console.error("--on-new command hooks are disabled; handle new tweet manually");
          seen.add(tweet.id);
          saveState(args.state, seen, startedAt);
        }
      }
    } catch (error) {
      if (args.once) throw error;
      console.error(`${startedAt.toISOString()} poll failed: ${error.message}`);
    }

    if (args.once) break;
    await sleep(args.interval * 1000);
  } while (true);
}

function printHeader(result) {
  console.log(`source=${result.source}`);
  console.log(`sourceKind=${result.sourceKind}`);
  console.log(`transport=${result.transport}`);
  console.log(`authUsed=${result.authUsed} xApiUsed=${result.xApiUsed} xAiUsed=${result.xAiUsed}`);
  if (result.stale) console.log(`stale=true reason=${result.staleReason}`);
  console.log(`tweets=${result.count} showing=${result.tweets.length}`);
}

function loadState(path) {
  if (!existsSync(path)) return { seen: [] };
  const raw = readFileSync(path, "utf8").trim();
  if (!raw) return { seen: [] };
  return JSON.parse(raw);
}

function saveState(path, seen, checkedAt) {
  const state = {
    checkedAt: checkedAt.toISOString(),
    seen: [...seen].slice(-1000),
  };
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(state, null, 2)}\n`);
}

function loadCache(path) {
  if (!path || !existsSync(path)) return null;
  const raw = readFileSync(path, "utf8").trim();
  if (!raw) return null;
  return JSON.parse(raw);
}

function saveCache(path, result) {
  if (!path) return;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(result, null, 2)}\n`);
}


function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchPublicUrl(url) {
  const response = await fetch(url, {
    redirect: "follow",
    signal: AbortSignal.timeout(20000),
    headers: {
      "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126 Safari/537.36",
      Accept: "text/html,application/xhtml+xml",
    },
  });
  if (!response.ok) {
    throw new Error(`public endpoint returned HTTP ${response.status}`);
  }
  return await response.text();
}

async function fetchSyndicationUrl(url) {
  const parsed = new URL(url);
  if (parsed.protocol !== "https:" || parsed.hostname !== SYNDICATION_ENDPOINT_HOST) {
    throw new Error(`refusing curl fetch for unexpected host: ${parsed.hostname}`);
  }

  let stdout;
  let stderr;
  try {
    ({ stdout, stderr } = await execFileAsync(
      CURL_BIN,
      [
        "-sS",
        "-L",
        "--max-time",
        "20",
        "-A",
        PUBLIC_UA,
        "-H",
        "Accept: text/html,application/xhtml+xml",
        "-w",
        `\n${CURL_STATUS_MARKER}%{http_code}`,
        url,
      ],
      { maxBuffer: 5 * 1024 * 1024 },
    ));
  } catch (error) {
    const message = error.stderr || error.message;
    throw new Error(`syndication curl failed: ${String(message).trim()}`);
  }

  const markerIndex = stdout.lastIndexOf(CURL_STATUS_MARKER);
  if (markerIndex === -1) {
    throw new Error(`syndication curl returned no status marker${stderr ? `: ${stderr.trim()}` : ""}`);
  }

  const body = stdout.slice(0, markerIndex).replace(/\n$/, "");
  const status = Number(stdout.slice(markerIndex + CURL_STATUS_MARKER.length).trim());
  if (status < 200 || status >= 300) {
    throw new Error(`syndication endpoint returned HTTP ${status}`);
  }
  return body;
}

main().catch((error) => {
  console.error(`peeper failed: ${error.message}`);
  process.exitCode = 1;
});
