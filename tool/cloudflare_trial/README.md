# Cloudflare trial (S2)

A one-shot, disposable-account trial that settles the facts the Cloudflare
publishing plan treats as load-bearing. It is **not** shipped in the app and is
deleted in S11.

Authoritative plan: [`cloudflare_plan-final.md`](../../cloudflare_plan-final.md)
Part L (safety and checks) and Part B (the facts being verified).

## What it needs

- A **throw-away Cloudflare account**.
- One API token created with exactly **`Workers Scripts · Edit`**, scoped to
  that one account — the same shape the app will ask users for. A broader token
  may be used only to diagnose a failed restricted call, never as proof that the
  production flow works.
- Nothing else. No app build, no device.

## Run

```bash
CF_API_TOKEN=... fvm dart run tool/cloudflare_trial/main.dart
```

Optional environment:

| Variable | Meaning |
|---|---|
| `CF_ACCOUNT_ID` | Skip account listing. Required when listing is refused or truncated. |
| `CF_CREATE_SUBDOMAIN=1` | Allow creating the permanent account subdomain. Throw-away accounts only. |
| `CF_TRIAL_SKIP_LARGE=1` | Skip the ~2,000-file bucket measurement (T5b). |

Exit codes: `0` every check passed, `1` a check failed, `2` no usable token.

## What it does

| Check | Question |
|---|---|
| T1 | Does the restricted token verify as active, and does it carry an expiry? |
| T2 | Can accounts be listed (bounded to 4 pages of 50), or is the manual Account ID path required? |
| T3 | Can the account subdomain be read, checked and (only if allowed) created? |
| T4 | Does the upload session accept leading-slash manifest keys and request every unique hash? |
| T5 | Does a bucket upload with per-part content types return a completion JWT, and are duplicate hashes deduplicated? |
| T6 | **Does a metadata-only assets deploy succeed?** If not, the plan stops. |
| T7 | Which field controls version URLs, and does it move when toggled? |
| T8 | Root/index/JSON/404 behaviour, content types, `no-cache` and CORS. |
| T9 | Is the deployment id available (diagnostics only)? |
| T10 | Does a second deploy dedupe unchanged files and remove the dropped `events.json`? |
| T11 | With version URLs off, is the earlier version unreachable? |
| T12 | Does a retired deploy serve the moved page, a 404 for `books.json`, the retired marker and the full CSP headers? |
| T13 | Is the trial Worker deleted and verified absent? |
| T14 | **Manual:** is there a supported conditional-deployment contract? Record the evidence. |
| T15 | Does turning version URLs on make the earlier version reachable (proving the gate matters)? |
| T5b | How does the API bucket ~2,000 × 100 KB assets? (informational) |

## Safety rules it enforces

- The token comes only from `CF_API_TOKEN`; it is shape-checked before any
  request and never printed, logged or put in an exception.
- Upload and completion JWTs live in private fields for one operation. They are
  never printed, never written to the report and never persisted.
- The report contains **fixed labels only**: status codes, numeric error codes,
  counts, booleans and whitelisted headers. No raw response body, no
  authorization header, no token.
- The Worker is named `pitak-trial-<8 hex>` and deletion is attempted in a
  `finally` block after every outcome. A cleanup failure is reported, not
  hidden.
- API traffic goes only to `https://api.cloudflare.com/client/v4`; redirects are
  refused; response bodies are capped at 1 MiB and cancelled past it.

## What it does not do

- It does not prove the app's HTTP adapter (that is S6) — it proves the API
  contract.
- It does not decide T14 for you: conditional writes are a documentation and
  source review, recorded by hand.
- It does not touch a real library, a real Worker or a real account subdomain
  unless you explicitly allow the last one.

## After the run

1. Paste the sanitized report into `cloudflare_plan-final.md` Part M (or attach
   it to the PR) and record the two decisions it settles: **T6** (metadata-only
   deploy) and **T14/T15** (conditional writes, version-URL gate).
2. If T6 failed, stop: shipping Worker code is a separate product decision.
3. If T14 found no conditional contract, the single-writer limitation in
   ADR 0017 becomes an operating requirement for the docs and store answers.
4. Check the asset-hash formula (deviation 49): if the session asked for hashes
   the app could not produce, the SHA-256 formula is wrong and the blake3
   question needs a product decision.
