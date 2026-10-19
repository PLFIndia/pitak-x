# Architecture Decision Records

One page per non-obvious architectural decision (AGENTS §0). Use
`0000-template.md` for new entries; number sequentially; never renumber or
delete — mark superseded instead.

| ADR | Decision |
|-----|----------|
| [0001](0001-clean-architecture-riverpod-di.md) | Clean Architecture + DDD with Riverpod codegen as the only DI |
| [0002](0002-fpdart-either-result-type.md) | `fpdart` `Either<Failure, T>`; no exceptions across layers |
| [0003](0003-sealed-hierarchies-over-pure-ocp.md) | Sealed hierarchies over "pure" OCP |
| [0004](0004-book-validate-ingress-gate.md) | `Book.validate` static ingress gate instead of a private constructor |
| [0005](0005-vault-key-in-rust-rewrap-not-rotation.md) | Vault key lives in Rust; passphrase change is rewrap, not rotation |
| [0006](0006-no-vault-auto-lock.md) | No vault auto-lock; app-lock is a screen cover |
| [0007](0007-string-tokens-for-http-apis.md) | `String` accepted for GitHub token + ISBN key |
| [0008](0008-flavor-split-kotlin.md) | Flavor-split Kotlin instead of Google-dependent plugins |
| [0009](0009-archive-package-in-domain.md) | `archive` allowed in domain for bounded zip extraction |
| [0010](0010-no-cert-pinning-github.md) | No certificate pinning for GitHub |
| [0011](0011-book-repository-isp-deferred.md) | `BookRepository` ISP split deferred |
| [0012](0012-library-network-replaces-bookmarks.md) | Library network replaces bookmarks; the fingerprint — not the raw library ID — is the published identity |
