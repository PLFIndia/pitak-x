# Security Policy

## Supported versions

Only the **latest tag** is supported with security fixes. The F-Droid build
may lag one release behind Google Play — check the installed version in
Android's app details (or `pubspec.yaml` for a source checkout) before
reporting.

## How to report a vulnerability

Use **GitHub private vulnerability reporting** on this repository
(Security tab → "Report a vulnerability"). This keeps the report private
until a fix ships, and requires no email address or PGP key on either side.

Please do **not** open a public issue for a suspected vulnerability.

## In scope

- Vault cryptography and the biometric key path
  (`rust/`, `lib/features/vault/`, `lib/core/crypto/`)
- The `.pitabak` backup format and restore path (including Kotlin-app
  archive compatibility)
- Import parsers (CSV / JSON / ZIP handling)
- The published-catalogue reader (`PublishedCatalogueCodec`, its bounded
  fetch/query adapters and the cover resolver) — remote JSON/image parsing
  from untrusted public sites and the viewer's origin/directory policy
- Publish flow token handling (GitHub credentials)
- The optional biometric app-lock

## Known limits — by design, not vulnerabilities

These are documented, deliberate trade-offs (see `README.md` › "Security
notes (honest limits)"). Please do not report them as vulnerabilities:

- **No vault auto-lock timeout** — an unlocked vault stays in memory until
  locked by the user or the app exits; backgrounding does not lock it.
- **`.pitabak` archives are not fully encrypted** — books, magazine-series
  and issue records, other items, wishlist, covers, item-kind mappings,
  library identity and the saved-libraries list are plaintext inside the
  archive; only the borrowers vault and its wrapped key blob are encrypted.
- **Passphrase change is a rewrap, not key rotation** — an old vault copy
  plus the old passphrase still opens that copy.
- **App-lock ≠ vault lock** — the optional app gate is a screen cover; it
  does not lock or encrypt the vault.
- **`String` tokens for GitHub / ISBN APIs** — their HTTP/plugin APIs are
  `String`-typed, so those two tokens transit as immutable strings and
  cannot be wiped from memory like the vault passphrase is.

## Response

- Acknowledgement within **7 days** (solo maintainer — this is an honest
  commitment, not a SLA).
- A fix is released to **both** stores (Google Play and F-Droid) before any
  public disclosure.
- Reporter credit in the release notes on request.

## Privacy

See `PRIVACY.md` for the app's data-handling posture (no telemetry, no
crash reporting, no analytics — by design).
