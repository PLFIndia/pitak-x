# AGENTS.md

> **Authoritative engineering contract for all AI agents and human contributors.**
> This file governs how code is written, reviewed, and refactored in this repository.
> When in doubt, **prefer correctness and security over speed or convenience.**
> If a requested change violates a rule here, **stop and surface the conflict** instead of silently complying.

---

## 0. Operating Context (READ FIRST)

- **The lead developer is a beginner.** Optimize for clarity, safety, and teachability.
- **Explain decisions in plain language.** When you make a non-obvious choice, add a short comment or PR note saying *what* and *why* in beginner-friendly terms.
- **Never patchwork.** When faced with two paths — a quick hack vs. a proper, secure, robust solution — **always choose the proper solution**, even if it is more code. Do not bolt fixes onto broken foundations; fix the foundation.
- **No magic.** Prefer explicit, readable code over clever one-liners the developer cannot maintain.
- **Teach as you build.** If a pattern is introduced (Value Object, Notifier, Result type), include a one-line comment explaining its purpose the first time it appears in a feature.
- **One blessed way.** Do not introduce alternative libraries or patterns for problems already solved in this repo. Consistency over novelty.

---

## 1. Project Identity

- **Stack:** Flutter (stable channel) / Dart (null-safe, latest stable SDK).
- **Architecture:** Clean Architecture + Domain-Driven Design (DDD).
- **State management:** **Riverpod** (with code generation via `riverpod_generator`). This is the single, non-negotiable choice.
- **Non-negotiables:** Security, scalability, testability, deterministic behavior.
- **Mindset:** Treat every input as hostile, every secret as a liability, every dependency as a risk.

---

## 2. Golden Rules (Agent Behavior)

1. **Never invent APIs.** If a class, method, or package symbol is uncertain, verify it against the actual `pubspec.yaml`, source, or generated code before using it.
2. **No silent assumptions.** If requirements are ambiguous, ask a clarifying question or state explicit assumptions in code comments and the PR description.
3. **No partial security.** A feature is not "done" if it leaks secrets, skips validation, or bypasses the layering rules below.
4. **No dead code, no TODO dumps.** Remove unused imports, variables, and branches. Convert `// TODO` into tracked issues, not silent debt.
5. **Idempotent edits.** Re-running the same task must not duplicate code, providers, or registrations.
6. **Explain trade-offs.** When choosing between approaches (e.g., `String` vs `Uint8List` for secrets), document *why* in a comment — written for a beginner.
7. **Fail closed.** On error, default to the most restrictive / safest behavior (deny access, wipe buffers, abort).
8. **Robust over quick.** Reject patchwork. If the correct fix requires refactoring, do the refactor and explain it.

---

## 3. Clean Architecture Layering

Strict dependency rule: **dependencies point inward only.** Inner layers know nothing about outer layers.

```
presentation  ->  application  ->  domain  <-  infrastructure
   (UI/State)     (use cases)     (pure)      (impl/IO/db)
```

### 3.1 Layer Contracts

| Layer | Allowed to depend on | MUST NOT contain |
|-------|----------------------|------------------|
| `domain` | nothing (pure Dart) | Flutter imports, IO, JSON, HTTP, DB, `dart:io`, Riverpod |
| `application` | `domain` | Widgets, `BuildContext`, concrete repositories |
| `infrastructure` | `domain` (implements its interfaces) | UI, business rules |
| `presentation` | `application`, `domain` | direct DB/HTTP calls, business logic |

### 3.2 Folder Convention

```
lib/
  core/                # cross-cutting: errors, result types, security utils, DI
  features/
    <feature>/
      domain/
        entities/
        value_objects/
        repositories/    # abstract interfaces only
        usecases/
      application/        # Riverpod Notifiers/AsyncNotifiers, DTO<->entity mapping
      infrastructure/
        models/           # DTOs, freezed JSON models
        datasources/
        repositories/     # concrete impls of domain interfaces
      presentation/
        pages/
        widgets/
        state/            # UI-only view state if needed
```

### 3.3 Rules
- **Domain entities are immutable** and validated at construction (use Value Objects).
- **No leaking of DTOs** (`*Model`) into domain or presentation. Map at the infrastructure boundary.
- **Repositories** are declared in `domain`, implemented in `infrastructure`.
- **Use cases** are single-responsibility, return a `Result`/`Either`, never throw for expected failures.
- **The domain layer never imports Riverpod.** Providers live in `application`/`core` only.

---

## 4. Riverpod Conventions (Single Blessed Way)

- **Always use code generation.** Declare providers with `@riverpod` and run `dart run build_runner build`. Do not hand-write `StateProvider`/`StateNotifierProvider` legacy syntax.
- **Provider types:**
  - Stateless dependency (repository, use case, data source) -> simple `@riverpod` function provider.
  - Async screen/feature state -> `@riverpod` class extending the generated `AsyncNotifier`.
  - Synchronous local state -> `@riverpod` class extending the generated `Notifier`.
- **Dependency Injection:** wire repositories and data sources through providers in `core/di/` (or a `providers.dart` per feature). No `GetIt`, no service locators — Riverpod is the DI container.
- **UI consumes via `ConsumerWidget` / `ConsumerStatefulWidget`** and `ref.watch` / `ref.read`.
  - `ref.watch` in `build` for reactive state.
  - `ref.read` inside callbacks/handlers for one-off actions.
- **Override providers in tests** with `ProviderContainer(overrides: [...])` — never reach into globals.
- **Auto-dispose by default.** Keep providers `autoDispose` (the codegen default) unless state must survive navigation; justify any `keepAlive` in a comment.
- **No business logic in providers' constructors.** Initialize via `build()`.
- **Dispose secrets in providers** using `ref.onDispose(() => secret.dispose())`.

```dart
// application/auth/login_controller.dart
@riverpod
class LoginController extends _\$LoginController {
  @override
  FutureOr<void> build() {
    // No initial work; UI is idle until submit() is called.
  }

  Future<void> submit(SecretBytes password, EmailAddress email) async {
    state = const AsyncLoading();
    final result = await ref.read(loginUseCaseProvider)(email, password);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    // Secret is wiped by the use case / caller after this returns.
  }
}
```

---

## 5. Error Handling & Result Types

- Use **`fpdart`'s `Either<Failure, T>`** as the single Result type across the codebase (chosen for active maintenance and good docs). Do not mix in `dartz` or hand-rolled variants.
- **Never** use exceptions for control flow across layers.
- Expected failures (validation, not-found, auth) -> typed `Failure`.
- Unexpected failures (bugs) -> log, wipe sensitive state, fail closed.
- Sealed failure hierarchy lives in `core/error/`.
- In the UI, map `AsyncValue`/`Either` to states explicitly: loading, error (show safe message), data. Never show raw exception text to users.

```dart
sealed class Failure {
  const Failure();
}
final class ValidationFailure extends Failure { const ValidationFailure(); }
final class AuthFailure extends Failure { const AuthFailure(); }
final class NetworkFailure extends Failure { const NetworkFailure(); }
final class UnexpectedFailure extends Failure { const UnexpectedFailure(); }
```

---

## 6. Security: Sensitive Data Handling (CRITICAL)

> Dart `String` is **immutable and UTF-16 heap-allocated**. You **cannot reliably wipe a `String` from memory**. The GC may copy or retain it indefinitely. Therefore secrets must **never live as `String` longer than unavoidable.**

### 6.1 Secret-Bearing Types
- **NEVER** store passwords, tokens, private keys, seed phrases, PINs, or symmetric keys in `String` for longer than the immediate parse step.
- **DO** hold secrets in **mutable byte buffers**: `Uint8List` (or `List<int>`).
- **DO** wipe buffers explicitly after use:

```dart
void wipe(Uint8List buffer) {
  for (var i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
}
```

- For char-level handling, prefer `List<int>` of code units you control, and zero them out.
- Wrap secrets in a `SecretBytes` type that:
  - exposes bytes only via a scoped callback (`use((bytes) => ...)`),
  - zeroes itself on `dispose()`,
  - throws if accessed after disposal,
  - overrides `toString()` to return `'SecretBytes(***)'` (never the value).
- In Riverpod, always register cleanup: `ref.onDispose(secret.dispose)`.

```dart
final class SecretBytes {
  SecretBytes(this._bytes);
  final Uint8List _bytes;
  bool _disposed = false;

  R use<R>(R Function(Uint8List bytes) action) {
    if (_disposed) throw StateError('SecretBytes used after dispose');
    return action(_bytes);
  }

  void dispose() {
    if (_disposed) return;
    for (var i = 0; i < _bytes.length; i++) {
      _bytes[i] = 0;
    }
    _disposed = true;
  }

  @override
  String toString() => 'SecretBytes(***)';
}
```

### 6.2 Logging & Serialization
- **NEVER** log, print, or `toString()` a secret, token, or PII field.
- Annotate sensitive fields and **exclude them from `freezed`/JSON serialization** unless encrypted.
- Override `toString()` on entities containing secrets to redact (`***`).
- Strip secrets from crash reports, analytics, and breadcrumbs.

### 6.3 Storage
- Use `flutter_secure_storage` (Keychain / Keystore) for tokens and keys — **never** `SharedPreferences` for secrets.
- Encrypt sensitive at-rest data; never store plaintext credentials.
- On logout / session end: wipe in-memory secrets, clear secure storage entries, invalidate tokens server-side, and `ref.invalidate` related providers.

### 6.4 Transport & Crypto
- TLS only; enforce certificate pinning for sensitive endpoints where feasible.
- Use vetted crypto libs (e.g., `cryptography`/`pointycastle`). **Do not roll your own crypto.**
- Use constant-time comparison for secret/MAC checks (avoid `==` on secret bytes).
- Generate randomness with a CSPRNG (`Random.secure()`), never `Random()`.

### 6.5 Input Validation
- Validate **all** external input at the boundary (Value Objects + use cases).
- Treat deep links, clipboard, intents, and IPC as untrusted.
- Enforce length, charset, and range limits to prevent injection / overflow / DoS.

### 6.6 Platform Hardening
- Disable screenshots on secret-bearing screens (`FLAG_SECURE` / equivalent).
- Consider clearing sensitive fields on app backgrounding (`AppLifecycleState.paused`).
- Avoid passing secrets through method channels as `String`; use byte arrays.

---

## 7. State Management Rules (Riverpod)

- State classes are **immutable** (`freezed`).
- No business logic in widgets. UI reacts to state only.
- Use `AsyncValue` for anything involving IO; render its `.when(data, error, loading)` explicitly.
- Dispose controllers, subscriptions, and secret-bearing state via `ref.onDispose`.
- No global mutable singletons. Riverpod providers are the only shared state mechanism.
- Keep `ref.watch` out of callbacks; keep `ref.read` out of `build`.

---

## 8. Scalability & Performance

- **Modular by feature**, not by type — features must be independently testable and removable.
- Lazy-load heavy resources; paginate lists; never load unbounded collections into memory.
- Use `const` constructors everywhere possible.
- Use `select` on providers to rebuild only on the fields that matter.
- Offload CPU-heavy work to `Isolate.run` (keep secrets out of isolates unless wiped on both sides).
- Cache with explicit invalidation strategy; no stale-data leaks across users/sessions.
- Avoid `setState` cascades; keep rebuild scope minimal.

---

## 9. Dependencies

- Baseline blessed packages: `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `freezed`, `json_serializable`, `fpdart`, `flutter_secure_storage`, `cryptography`, `very_good_analysis`, `build_runner`.
- Pin versions; review transitive deps before adding.
- Justify every new dependency in the PR (size, maintenance, license, security history).
- Prefer first-party / well-maintained packages. Avoid abandoned (>12mo no release) libs for security-critical paths.
- Run `dart pub outdated` and audit advisories regularly.
- **Do not add a new package to solve a problem an existing blessed package already solves.**

---

## 10. Testing Requirements

- **Domain & application layers: high coverage (target ≥ 90%).**
- Every use case: success + each failure path tested.
- Every Value Object: validation boundary tests.
- **Riverpod tests:** use `ProviderContainer` with `overrides`; never hit real network/storage.
- **Security tests:** verify secrets are wiped, not logged, not serialized.
- Widget tests for critical flows; golden tests for key UI.
- No PR merges with failing tests or reduced coverage on touched code.

```dart
test('SecretBytes is zeroed after dispose', () {
  final secret = SecretBytes(Uint8List.fromList([1, 2, 3]));
  secret.dispose();
  expect(() => secret.use((b) => b), throwsStateError);
});

test('LoginController exposes AuthFailure on bad credentials', () async {
  final container = ProviderContainer(
    overrides: [
      loginUseCaseProvider.overrideWithValue(_FakeFailingLogin()),
    ],
  );
  addTearDown(container.dispose);
  // ... drive submit() and assert AsyncError(AuthFailure)
});
```

---

## 11. Code Quality & Tooling

- Enforce `very_good_analysis` or equivalent strict lints.
- `dart format` and `dart analyze` must pass with **zero warnings**.
- Run `dart run build_runner build --delete-conflicting-outputs` after changing any `@riverpod`/`freezed`/`json_serializable` annotated code. Commit generated files unless `.gitignore`d intentionally.
- No `// ignore:` without an explicit justification comment.
- Public APIs documented with `///` doc comments.
- Naming: descriptive, no abbreviations for domain concepts.

### Required CI gates
- [ ] `dart run build_runner build --delete-conflicting-outputs` (no uncommitted diffs)
- [ ] `dart analyze` (zero issues)
- [ ] `dart format --set-exit-if-changed`
- [ ] `flutter test --coverage`
- [ ] Dependency / secret scan
- [ ] Architecture boundary check (no inward->outward imports; domain free of Riverpod/Flutter)

---

## 12. Git & PR Discipline

- Small, atomic commits. Conventional Commits (`feat:`, `fix:`, `refactor:`, `sec:`).
- **Never commit secrets, `.env`, keystores, or tokens.** Enforce via `.gitignore` + pre-commit secret scanning.
- PR description must state: what changed, why, security impact, and test coverage.
- Security-relevant changes (`sec:`) require explicit reasoning in the description.

---

## 13. Agent Decision Checklist (run before finalizing any change)

Before producing code, the agent MUST confirm:

- [ ] Is this the robust, proper solution rather than a patch?
- [ ] Does this respect the layer dependency rule (domain free of Riverpod/Flutter)?
- [ ] Are providers declared with `@riverpod` codegen and properly disposed?
- [ ] Are all external inputs validated?
- [ ] Are any secrets handled as wipeable bytes, not `String`, and disposed via `ref.onDispose`?
- [ ] Are secrets excluded from logs, `toString()`, and serialization?
- [ ] Is failure handled via `Either<Failure, T>`, failing closed?
- [ ] Are tests added/updated (with `ProviderContainer` overrides), including security paths?
- [ ] Did I explain non-obvious choices in beginner-friendly terms?
- [ ] Is anything ambiguous that requires asking the user first?

If **any** box cannot be checked, **stop and report**, do not guess.

---

## 14. Hard Prohibitions

- ❌ Patchwork fixes over broken foundations — refactor properly instead.
- ❌ Legacy Riverpod syntax (`StateNotifierProvider`, manual `Provider((ref) => ...)`) when codegen applies.
- ❌ Service locators (`GetIt`) — Riverpod is the only DI.
- ❌ Storing secrets in `String`, logs, `SharedPreferences`, or analytics.
- ❌ Business logic inside widgets.
- ❌ Domain layer importing Flutter, Riverpod, or IO.
- ❌ Hand-rolled cryptography.
- ❌ Swallowing exceptions silently.
- ❌ Catch-all `catch (e) {}` without handling/logging/rethrow.
- ❌ Disabling lints to "make it compile."
- ❌ Committing generated secrets, keys, or credentials.

---

*This document is the source of truth. Update it deliberately; treat changes to security rules as security-critical PRs.*