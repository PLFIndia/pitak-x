# ADR 0023: Borrower lending limits

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

A maintainer needs to cap how many items one borrower has out at once. Every
active loan counts separately, including two copies of one title. The existing
item-availability decision runs before a borrower is chosen, so it cannot own
this second rule. All production loan writes pass through the vault session's
FIFO, but a lend form can hold a stale loan snapshot while earlier writes are
queued.

The rule is device-local policy, not vault material: it stores no borrower
identity, count or history. Warn mode permits an explicit override; Refuse mode
promises no override and therefore cannot rely only on that stale outer
snapshot. An unreadable policy must not silently become "off".

The cap-plus-separate-override shape is inspired by Koha circulation rules;
no code or unverified configuration identifiers are borrowed.

## Decision

1. **One optional policy.** The limit is off by default or 1–99 active loans
   per borrower. At-or-over triggers the configured Warn or Refuse action.
   Returned-loan inserts and all return/delete flows are unaffected.
2. **Two-phase Warn outcome.** `LendBookUseCase` returns `LoanRecorded` or
   `LimitConfirmationNeeded(limit, active)` instead of `Unit`. Confirmation
   writes nothing. The page captures the original target, borrower display
   name, dates and notes, disables inputs while busy, and retries that exact
   submission with an acknowledgement only after explicit confirmation.
   Cancel and dialog dismissal make no second call. Refuse ignores the
   acknowledgement.
3. **Split enforcement.** Warn is a best-effort outer use-case check. Refuse
   also reloads the policy and recounts the borrower's active loans inside
   `VaultSessionController.addLoan`'s `_mutate` FIFO before insertion. The
   narrow `VaultLender` signature stays unchanged; the session controller is
   the only production loan writer and re-reads after successful mutations.
4. **Strict local recovery.** ADR 0022's versioned SharedPreferences JSON
   pattern stores only the limit, action and schema version. Wrong, oversized
   or unreadable data fails lending closed with a recovery message. Lending
   rules are always visible from the vault app bar, including while locked,
   and the editable error-state form can overwrite a bad document.

## Consequences

- Domain, store, use-case, controller, FIFO-race and widget tests pin boundary
  validation, strict decoding, no-write confirmation, identical captured
  retries, fail-closed reads and the overlapping-Refuse re-check.
- The policy is excluded from backup/export and contains no borrower PII. No
  network, telemetry, permission or dependency is added.
- Per-borrower custom limits, per-kind limits and borrower-list count badges
  remain separate follow-ups. The locked vault golden changes because the
  Lending rules action is intentionally visible before unlock.
