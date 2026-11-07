# Architecture Decision Records

One page per non-obvious architectural decision (AGENTS §0). Use
`0000-template.md` for new entries; number sequentially; never renumber or
delete — mark superseded instead.

| ADR | Decision |
|-----|----------|
| [0001](0001-clean-architecture-riverpod-di.md) | Clean Architecture + DDD with Riverpod codegen as the only DI |
| [0002](0002-fpdart-either-result-type.md) | `fpdart` `Either<Failure, T>`; no exceptions across layers |
| [0003](0003-sealed-hierarchies-over-pure-ocp.md) | Sealed hierarchies over "pure" OCP |
| [0004](0004-book-validate-ingress-gate.md) | `Book.validate` static ingress gate instead of a private constructor (the entity is `CatalogueItem` since 2026-10) |
| [0005](0005-vault-key-in-rust-rewrap-not-rotation.md) | Vault key lives in Rust; passphrase change is rewrap, not rotation |
| [0006](0006-no-vault-auto-lock.md) | No vault auto-lock; app-lock is a screen cover |
| [0007](0007-string-tokens-for-http-apis.md) | `String` accepted for the GitHub, ISBN and Cloudflare tokens, plus ephemeral Cloudflare upload JWTs |
| [0008](0008-flavor-split-kotlin.md) | Flavor-split Kotlin instead of Google-dependent plugins |
| [0009](0009-archive-package-in-domain.md) | `archive` allowed in domain for bounded zip extraction |
| [0010](0010-no-cert-pinning-github.md) | No certificate pinning for the publishing APIs (GitHub, Cloudflare) |
| [0011](0011-book-repository-isp-deferred.md) | `BookRepository` ISP split deferred (now `CatalogueItemRepository`) |
| [0012](0012-library-network-replaces-bookmarks.md) | Library network replaces bookmarks; the fingerprint — not the raw library ID — is the published identity |
| [0013](0013-catalogue-item-kinds.md) | Catalogue item kinds: one base row per item of any kind, per-kind detail tables, the base row is the lendable unit; magazines/issues/periodicals and Others |
| [0014](0014-catalogue-interchange-and-backup.md) | Item kinds in Pitaka-JSON (v4), `books.json` (additive) and `.pitabak` (`item_kinds.json` / `periodicals.json`); amended 2026-11-02: `publish_state.json`, the website publishing record a restored phone adopts only if it has not published itself |
| [0015](0015-native-saved-library-viewer.md) | A saved network row opens a read-only native view of its published `books.json`; no WebView, no persistent cache, memory-only consent-gated covers |
| [0016](0016-native-published-events.md) | Native Announcements & Events use an independently-published, bounded `events.json`; no HTML scraping or WebView |
| [0017](0017-cloudflare-workers-publishing.md) | Cloudflare Workers publishing: a dedicated assets-only Worker, one active host, complete snapshots, an exact target/journal, marker freshness and the disclosed single-writer limitation; amended 2026-11-02: a GitHub catalogue or events publish returns at commit time and is proven live afterwards (plan SP1), and Cloudflare's read-back and preflight send their independent reads side by side with unchanged budgets and outcomes (plans SP2, SP3); amended 2026-11-03: a GitHub publish skips the file-list read when the branch head is still its own proven commit, and a GitHub Pages site carries `.nojekyll` (plans SP4, SP5) |
| [0018](0018-revalidated-saved-copies-of-published-files.md) | A saved library's `books.json`/`events.json` are kept as verified saved copies in the OS cache directory, revalidated with the host's `ETag` on every open (`304` = no download), shown with a note when the host can't be checked; 200 MiB cap, least recently opened evicted first (supersedes ADR 0015 decision 3) |
| [0019](0019-availability-fast-lane.md) | Availability fast lane: loans publish a tiny `availability.json` (keys of items that are not available) by themselves while the app runs, joined to `books.json` by a salted per-item `key`; no cover work, every ADR 0017 gate kept, paced for GitHub's build limit; on by default with a Settings switch (amends ADR 0015, 0017, 0018); Decision 3 clarified 2026-11-04: a publish reads the cover salt once and derives its keys, key-set id and cover file names from that one read (plan S16, Fix 4) |
| [0020](0020-publish-work-avoidance.md) | Publish work avoidance and speed: a cover already online is reused unread when the record names the same source and the current cover rendition; stored cover files never change; a restore forgets local cover sources; complete snapshots still read every cover; then GitHub blob reuse, backup publish state, and the Phase 3 speed work; Decision 11 (2026-11-04): the cover salt is read once per publish, so an unchanged republish of 1,000 covers no longer spends 73 s opening secure storage (plan S16, Fix 4) |
| [0021](0021-restore-from-own-published-site.md) | Restore an empty catalogue from the user's own active published site; defensive mapping, transactional emptiness, durable fingerprint recovery, pre-publish and Cloudflare no-destruction guards, consented bounded covers, and fingerprint carry-over in backups |
| [0022](0022-borrowed-items-loan-reminders.md) | Vault-gated Borrowed Items, shared loan urgency/date rules, bounded Unicode templates in atomic plaintext preferences, sanitized local covers, and explicit generic OS reminder sharing |
| [0023](0023-borrower-lending-limits.md) | Optional per-borrower active-loan cap; two-phase Warn confirmation with an identical captured retry, FIFO-hard Refuse, strict local policy recovery, and always-visible Lending rules |
| [0024](0024-background-event-alerts.md) | Android-only background event alerts for user-saved libraries: 12 h WorkManager job, read-only peeked-generation SQLite source, two single-writer bounded documents with incarnation + epoch identity, quiet baselines, withheld `304`/`404`/partial reads, stable replace-by-id grouped notifications with public-name-only titles, revocation marker, explicit Resume; default ON offered with an explanation |
