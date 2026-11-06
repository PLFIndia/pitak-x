# Borrowed Items and loan reminders — implementation plan

- **Status:** Implementation complete on `reminders`; pubspec OSV scan and real-device verification pending
- **Date:** 2026-11-06
- **Scope:** Borrowed Items navigation/page, active-loan cards, reusable message templates, and cover-plus-caption reminder sharing

## Understanding

The current **Borrowers vault → Pending** screen classifies overdue and due-soon loans, but its rows show only `Item #id` and a due date. It does not show the catalogue cover/title or borrower contact actions. The maintainer wants a catalogue-like **Borrowed Items** destination where each active loan is recognizable and a WhatsApp action prepares a reminder containing the item's cover and message text. Nothing is sent automatically.

Custom templates are also required. A maintainer can write and save named templates in Hindi or any other language, choose one as the default, and have every reminder reuse it with the item title and, for dated loans, the due date filled in.

### Goals

- Add **Borrowed Items** to the left drawer, near **Borrowers vault**.
- Show one catalogue-style entry per **active loan**, including multiple loans of different copies of the same item.
- Support **All**, **Overdue**, **Due soon (72 hours)**, and **No due date** filters; use the existing overdue/rolling-72-hour rules.
- Show cover, title, author, due status/date, borrower name, available phone number, Call, a generic reminder-share action, and a direct WhatsApp text action when a phone number is available.
- On one WhatsApp tap, prepare the selected message and local cover together for maintainer-reviewed sharing.
- Persist named Unicode templates and the selected default across app restarts.
- Reuse existing architecture, packages, cover rendering, contact parsing, image sanitization, and sharing seams.

### Non-goals

- Automatically sending a message or claiming that a share hand-off proves delivery.
- Guaranteeing a preselected WhatsApp conversation when an image is attached.
- Background/push notifications, translation, language detection, or cloud synchronization.
- Downloading a remote cover merely to send a reminder.
- Adding a WhatsApp-specific native Android channel in the first implementation.
- Replacing Pending, adding Return actions, or adding template backup/export in this change.

## Privacy & threat notes

- **Vault gate the whole loan list.** Active-loan facts and borrower details come from the encrypted vault. While locked/uninitialized, show an unlock/setup route, not titles of borrowed items or stale entries from an earlier unlocked state. Do not add an unencrypted loan index. Re-check the session after asynchronous preparation before opening an external share.
- **Explicit external disclosure only.** Tapping WhatsApp is the user's choice to hand the item title, due message, and cover to the generic OS share flow. No background share, telemetry, recipient lookup, or automatic Send. The app does not detect or claim that WhatsApp is installed.
- **Recipient limitation is visible.** The maintainer chooses WhatsApp and the conversation in the external flow. The app must not imply that the borrower was preselected or that the message was sent. Choosing another target or dismissing is also valid.
- **Sanitize and bound images.** Read local covers under an explicit streamed byte cap, then re-encode through `ImageDownscaler` so EXIF/GPS metadata is stripped and decoder dimension/pixel limits apply. Never fall back to raw image bytes. A local reference that is missing, unreadable, unsafe, oversized, or corrupt is a preparation failure, not a silent text-only fallback.
- **No silent network fetch.** A remote-only cover is treated as unavailable for image sharing unless it was already materialized locally through the existing consent-gated flow. Borrowed Items cards pass `owner: null` to `ItemCover`, so merely viewing this page cannot start a download.
- **Plaintext template warning.** Persist template definitions and the selected template ID—never rendered messages, recipients, or share history. The app never inserts borrower details into a template, but free-form template text can contain anything the maintainer types and is stored unencrypted in preferences. The editor must say not to include private details. Do not log template bodies or rendered messages.
- **Share-cache honesty.** No reminder history or app-owned persistent reminder copy is written. The pinned `share_plus` implementation does create a temporary cover file in its app-cache directory while sharing; OS/plugin cleanup or a later Android share removes it. Do not claim that no bytes ever reach disk.
- **Bound user input and stored data.** Limit template count, label/body lengths, stored JSON size/depth, and rendered message length. Label/body/message caps are UTF-16 code units (`String.length`); the 64 KiB document cap is UTF-8 bytes. Reject wrong-typed, malformed, excessive, or newer-version input rather than treating it as absent.
- **Screen and app lock.** Existing unlocked-vault policy already applies Android `FLAG_SECURE`; no page-level toggle is needed, and equivalent iOS/desktop protection must not be implied. The optional global app lock re-gates on return from an external share and is not suppressed. This is separate from the vault session, which deliberately remains unlocked in memory behind that gate.
- **Least privilege.** Use existing `share_plus`; add no package, Android permission, WhatsApp SDK, Google dependency, or F-Droid impurity.

## Investigation notes

- `lib/core/widgets/app_drawer.dart` owns drawer destinations and has widget navigation tests.
- `VaultUnlocked` exposes decrypted `VaultData`; locked/uninitialized states contain no loans (`lib/features/vault/domain/entities/vault_session_state.dart`).
- `lib/features/vault/domain/pending_snapshot.dart` defines overdue as `now > dueDate` and due soon as not overdue and due within a fixed 72-hour millisecond window, not three calendar days across DST transitions. `Loan.isOverdue` already owns the same overdue comparison. `nowTickProvider` refreshes time-dependent UI every 60 seconds.
- Loan due dates are stored from the local date picker and Pending renders them with local `DateTime.fromMillisecondsSinceEpoch`. `CalendarDate.fromEpochMillis` reads UTC fields and must not format these instants.
- `CatalogueItemRow`, `CatalogueItemGridCard`, and `ItemCover` provide the visual baseline. `ItemCover` displays local files but can materialize a remote cover when `owner` is non-null; Borrowed Items must pass `owner: null`. Series-cover behavior remains consistent with `IssueCover`.
- `CatalogueItemRepository` has `getById` but no multi-ID read. A current scan finds 46 direct test implementers in 43 files, so expanding that interface has a broad test cost. V1 uses sequential reads per unique item ID (or a small fixed concurrency bound if needed), never an unbounded `Future.wait` and never a whole-catalogue read.
- `periodicalCoversProvider` deliberately converts a periodical `listAll` failure to an empty map, and Pending converts catalogue failure to an empty list. Neither fail-soft behavior is suitable for the borrowed-items snapshot.
- `BorrowerContact` parses phone numbers and builds sanitized dialer/WhatsApp contact URIs. `telUri != null` is the existing Call visibility rule; this is URI sanitization, not proof that the number is valid. Reminder sharing uses the OS share flow, not a `wa.me` message URL.
- `FileShareService.shareBytes` accepts bytes, filename, MIME type, caption text, and iPad origin; `shareText` is the text-only fallback. `ShareOutcome.success` means hand-off only, not sent/delivered (`lib/core/platform/file_share.dart`).
- `lib/features/publish/infrastructure/local_cover_reader.dart` re-encodes asynchronously with metadata stripping and no raw fallback, but currently buffers the whole file before decoding and returns `null` for every unavailable/failure case. `lib/core/platform/bounded_file_read.dart` supplies the tested streaming-cap pattern. Publish tests pin the downscaler defaults to the 400×600 q80 rendition.
- `PrefsPublishHostStore` demonstrates one versioned JSON preference key and `writePrefsString`, but its size checks are UTF-16 lengths. `PrefsAvailabilityLaneStore` demonstrates wrong-type handling with `_prefs.get`; `JsonNestingDepth` supplies the pre-parse depth guard. `SerialOpQueue` is the existing tested FIFO for serialized mutations.
- Pinned `share_plus` 12.0.2 documents both temporary cache files for `XFile.fromData` and receiving-app limitations for image-plus-text sharing. Existing `ShareLibrarySheet` usage proves the call shape, not WhatsApp caption behavior; real-device verification remains required.

## Proposed approach

### 1. Shared loan status and read model

Create pure-Dart domain types under `lib/features/vault/domain/`:

- `LoanUrgency`: `overdue`, `dueSoon`, `dueLater`, `noDueDate`.
- `loanUrgency(...)`: one boundary-tested classifier used by both Pending and Borrowed Items. It uses the existing `Loan.isOverdue` comparison rather than adding another overdue rule; returned-loan exclusion stays explicit in callers. Due soon retains the current rolling 72-hour rule.
- `BorrowedLoan`: immutable `CatalogueItem`, `Loan`, `Borrower`, urgency, and the exact display cover reference.
- `BorrowedItemsSnapshot`: ordered entries plus a count of unresolved active loans that cannot safely be displayed. Entries plus unresolved count determines whether any active loan exists.

Build the snapshot from the unlocked `VaultData` and only the referenced catalogue rows:

- Filter to `returnedDate == null`; keep active loans even if their catalogue item is soft-removed. No active loans means no catalogue or periodical query.
- Read the existing `CatalogueItemRepository.getById` once per unique `itemId`, sequentially in v1. If concurrency is later measured as necessary, use a small fixed bound. A repository `Left` fails the snapshot; a returned null is an unresolved reference. Do not expand the repository interface unless measurement later justifies `getByIds` and its test-fake updates.
- Join borrowers and items by ID. Skip and count missing item/borrower references using the `LoanIntegrity` rule rather than rendering actionable broken cards.
- Resolve the displayed cover once, including a magazine issue's series-cover fallback, so card and shared image agree. When fallback is needed, read `PeriodicalRepository.listAll` once and propagate its `Left`; do not use the fail-soft `periodicalCoversProvider`. A missing series means no fallback cover, not an unresolved loan.
- Order by due date ascending with nulls last, then title, borrower name, and loan ID for deterministic ties. Each active loan remains a separate entry.

Move Pending's local `10 November 2026`-style instant formatter into shared pure-Dart loan-domain code and use it for Pending, cards, and `{{dueDate}}`. Do not use `CalendarDate`, whose UTC calendar-day rule belongs to catalogue date-only fields.

Add an application read use case returning `Either<Failure, BorrowedItemsSnapshot>`. The Riverpod provider watches vault session, catalogue/periodical mutation signals, and `nowTickProvider`; vault-session loading/error, locked/uninitialized, unlocked empty, and repository failure are distinct states. A repository failure is never converted to "nothing borrowed" or to missing covers.

### 2. Borrowed Items page and navigation

Add `BorrowedItemsPage` and dedicated row/grid widgets under vault presentation. Reuse `ItemCover` with `owner: null` and the library's responsive layout breakpoint, but do not force borrower/contact behavior into generic catalogue widgets.

Page behavior:

- **Loading:** centered progress indicator for either vault-session or snapshot loading.
- **Locked/uninitialized:** plain explanation plus the existing **Unlock the vault** / **Set up the vault** route through `VaultPage`; returning after unlock rebuilds the list. Locking while visible must immediately hide every previously resolved title, borrower detail, and action.
- **Unlocked, no active loans:** "Nothing is currently borrowed" only when entries and unresolved count are both zero.
- **Read failure:** safe "Couldn't load borrowed items" state with Retry for vault-session, catalogue, or periodical read failures; no raw failure text and no unlock/empty misclassification.
- **Unresolved references:** show a non-sensitive warning count while rendering only complete entries; never expose contact actions for them. If every active loan is unresolved, show the warning and an explanatory state rather than "Nothing is currently borrowed."
- **Filters:** All, Overdue, Due soon (72 hours), No due date. Due-later loans remain in All. Show a specific empty-filter message.
- **Cards:** key by loan ID and show cover, title/author, kind where applicable, status badge, local formatted due date, borrower name, and decoded phone when present. Card tap opens the existing catalogue detail page.
- **Call:** shown when `BorrowerContact.telUri` is non-null and launched through the existing sanitized `tel:` path. This does not claim the phone number was verified.
- **Generic share:** uses the cover-plus-message share flow below with a generic share icon. It does not claim to preselect the borrower, detect WhatsApp, or exclude other share targets.
- **Direct WhatsApp text:** a separate WhatsApp icon appears only when `BorrowerContact.whatsappUri` is non-null. It renders the current caption without reading the cover and opens the borrower's `wa.me` conversation with that text prefilled. The maintainer still taps Send in WhatsApp.
- **Time/mutations:** a minute tick moves loans between statuses; lend/return/edit/rename/cover changes refresh the visible entries.

Use lazy list/grid builders and accessibility-friendly action buttons. Grid sizing must leave room for borrower/actions rather than reusing the catalogue's fixed 280-pixel card height blindly. Per-card busy state is keyed by loan ID so one loan of a multi-copy item never disables another.

### 3. Reusable Unicode message templates

Add an immutable `ReminderTemplate` domain model with a validating factory or static ingress gate:

- Stable generated `id` for custom templates.
- User-chosen `name` such as "English", "Hindi", or "ಕನ್ನಡ"; no locale code or translation service is needed.
- Separate `overdueBody`, `upcomingBody`, and `noDueDateBody`, because "is due" versus "was due" differs naturally across languages. `upcomingBody` serves both `dueSoon` and `dueLater`.

Provide one read-only built-in English template:

- Overdue: `Your loan of "{{itemTitle}}" was due for return on {{dueDate}}.`
- Upcoming: `Your loan of "{{itemTitle}}" is due for return on {{dueDate}}.`
- No due date: `Your loan of "{{itemTitle}}" is currently out on loan.`

Only two placeholders are supported: `{{itemTitle}}` and `{{dueDate}}`. Dates use the shared local `10 November 2026`-style loan formatter with fixed English month names, avoiding a second localization system. Template text itself remains verbatim Unicode, including Indic and right-to-left scripts. Do not add bidi isolate marks; ordering in the receiving app is its responsibility.

Template rules:

- Overdue/upcoming bodies must contain both `{{itemTitle}}` and `{{dueDate}}`; no-due-date bodies must contain `{{itemTitle}}` and must not contain `{{dueDate}}`. This preserves the goal that every dated reminder includes its due date. Making `{{dueDate}}` optional is a separate maintainer choice, not a silent simplification.
- Repeated known placeholders are allowed and each occurrence is rendered. Reject blank labels/bodies, unknown/unclosed/stray placeholder delimiters, excessive lengths, and more than 20 custom templates.
- Caps: 80 UTF-16 code units per label, 1,000 per body, 64 KiB of UTF-8 bytes for the stored JSON document, and 1,000 UTF-16 code units per rendered message. The body and rendered caps deliberately agree so a long body is not accepted while being inherently unshareable; rendering still enforces the cap because the item title can make the result longer. Editor errors explain that some scripts/emoji count as more than one visible character.
- Render with a single-pass token parser that appends values directly. Never chain `replaceAll` calls: a title containing `{{dueDate}}` must remain a title, not be interpreted as another placeholder. Substituted titles and dates are wrapped in WhatsApp's `*bold*` markers; the receiving app controls whether that emphasis renders.
- The built-in template cannot be edited or deleted. Custom templates can be added, renamed, edited, duplicated, and deleted. Deleting the selected custom template selects built-in English in the same persisted write.
- A missing/corrupt selected template must be visible in the template UI and must not silently switch a just-tapped Hindi reminder to English. Block sharing with a safe selection prompt if the selection cannot be resolved.

Persist custom templates and `selectedTemplateId` as one versioned JSON document in a dedicated `PrefsReminderTemplateStore`. A single key avoids template/selection write skew; keep the built-in template out of storage. Follow the host store's typed unreadable/write pattern, not its size implementation: use `_prefs.get` with wrong-type rejection, a cheap code-unit pre-reject before allocation, actual UTF-8 byte-cap checks on read and write, `JsonNestingDepth` before `jsonDecode`, strict field/list bounds, and `writePrefsString`. Corrupt, oversized, wrong-typed, or newer-version data is unreadable, never absent.

Add a keep-alive `ReminderTemplatesController` using the existing `SerialOpQueue` for serialized write-then-publish mutations, matching the settings controller's state semantics without copying its FIFO. Failed writes leave the last good state visible and return a typed failure. The Borrowed Items page shows the active template name and a selector; its app-bar **Message templates** action opens the manager. The selected default persists, so the WhatsApp button remains a single-tap action.

The template editor provides separate fields for the three statuses, placeholder-insertion chips, and a sample preview. Saving validates all three bodies and warns that template text is stored unencrypted and should not contain private details. No actual borrower or loan data is used in previews.

### 4. Cover-plus-caption reminder sharing

Create a pure message renderer and an application `PrepareLoanReminderUseCase` over an injected reminder-cover-reader port:

1. Read the current selected template at tap time and map `overdue` to `overdueBody`, `dueSoon`/`dueLater` to `upcomingBody`, and `noDueDate` to `noDueDateBody`, recomputing urgency from the injected clock.
2. Render the item title and, where applicable, the shared local `10 November 2026`-style due date in one pass. Enforce the 1,000-code-unit final cap. This is a conservative application limit, not a claim about WhatsApp's exact external caption limit.
3. Resolve the same display cover reference used by the card.
4. Promote the publish local-cover implementation into shared library infrastructure. It performs a streamed byte-bounded read (8 MiB, matching the existing remote-cover cap), then the existing asynchronous downscaler with its unchanged 400×600 q80 defaults and no raw fallback. Publishing keeps the same implementation through its nullable adapter; the reminder port returns a typed outcome rather than importing publish application/infrastructure code or duplicating file IO.
5. Return a sealed preparation result that distinguishes image-ready, text-only-eligible, and preparation failure. Image-ready contains sanitized JPEG bytes, `image/jpeg`, a safe fixed filename such as `loan-reminder.jpg`, and the rendered caption.

The card's WhatsApp handler first re-checks after every asynchronous preparation step that it is mounted and the vault is still unlocked; otherwise it aborts without a hand-off. It then calls `FileShareService.shareBytes` with the prepared bytes/caption and the button's global rect for iPad. This uses the existing OSS `share_plus` `ShareParams(files:, text:)` mechanism also used by `ShareLibrarySheet`, rather than inventing a WhatsApp API or adding a plugin. That existing call shape is not evidence of WhatsApp behavior; actual cover/caption hand-off must pass real-device verification before being claimed.

Exact behavior:

- **Usable local cover:** one tap on the generic share icon opens the OS share flow with cover and caption together. The maintainer chooses WhatsApp and the conversation, reviews/edits, and taps Send.
- **Direct text action:** the separate WhatsApp icon opens the borrower's conversation with only the caption prefilled. It performs no cover read and no generic share-service call, and never claims the message was sent.
- **Blank or remote-only cover reference:** do not fetch. Offer a clearly labelled text-only choice through `FileShareService.shareText`; never put the message in a `wa.me` URL.
- **Safe-local reference whose file is missing, or an unreadable/unsafe/oversized/corrupt cover:** show "Couldn't prepare the cover" and do not open a misleading image share or automatically fall back to text. A separate explicit text-only action may remain available.
- **Template invalid/unavailable or message too long:** block the hand-off and show a safe corrective message.
- **Busy:** disable only the tapped loan ID's action and collapse duplicate taps until preparation/hand-off completes.
- **Dismissed:** no error and no success claim.
- **Success:** no "sent" message; it means only that a target was chosen.
- **Unavailable/throw:** show fixed safe copy and restore the action. Catch platform exceptions at the presentation boundary; never log private details. Generic sharing being unavailable is not the same fact as WhatsApp not being installed.
- **App lock round trip:** do not use `LockSuppressor` for sharing. Returning from WhatsApp with the optional global app lock enabled prompts again while the vault session remains behind the gate.

No raw cover bytes, message text, template text, borrower name, or phone number enters logs. No reminder history or app-owned persistent reminder copy is written; the share plugin's temporary cache-file behavior is documented rather than denied.

## Implementation steps

- [x] **Review baseline:** at `58652ca`, 92 focused vault/contact/cover/share/bounded-read/FIFO/app-lock/screen-security tests passed under the pinned Flutter 3.44.2.
- [x] **Activate:** archived the finished 1.9.4 release record as `docs/plans/release-1.9.4-aab.md` and made this feature the active plan.
- [x] **Domain status:** extract the shared urgency classifier over `Loan.isOverdue`, migrate `buildPendingSnapshot` without behavior changes, add the local loan-date formatter, and add boundary tests.
- [x] **Catalogue/read model:** implement/test sequential per-unique-ID reads, active-loan joining, integrity handling, strict periodical-cover resolution, and deterministic ordering. Do not add `getByIds` in v1.
- [x] **Providers/UI:** add the borrowed-items provider, drawer destination, responsive cards, filters, locked/empty/error/unresolved states, and contact actions.
- [x] **Template domain/storage:** implement validation, single-pass rendering, built-in English, strict versioned preference persistence, and the `SerialOpQueue`-serialized controller.
- [x] **Template UI:** add manager/editor, default selector, CRUD, previews, plaintext-storage guidance, and safe corruption/write-failure handling.
- [x] **Sharing:** promote the cover reader with a streamed byte cap and typed reminder outcome, implement reminder preparation and card hand-off, including session rechecks and all fallback/outcome paths.
- [x] **Codegen:** run `dart run build_runner build --delete-conflicting-outputs` and review generated diffs.
- [x] **Docs:** add `docs/adr/0022-borrowed-items-loan-reminders.md`; update `docs/mockups/how-pitak-works.md` and its `.html` twin; update `PRIVACY.md` with plaintext templates, external sharing, and cache behavior; and note in `README.md` that templates are not in the current backup.
- [ ] **Verification:** automated gates pass except the unavailable pubspec OSV scanner and macOS-only golden renderer comparison; real-device WhatsApp/iOS checks and Play/F-Droid smoke remain. run all tests/checks below. Perform real-device WhatsApp checks before calling cover/caption hand-off verified; report unavailable platforms as unverified rather than passing them.

## Test plan

### Domain and application

- Urgency: no due date, due exactly now, one millisecond past due, exactly 72 hours ahead, beyond 72 hours, due today at noon already overdue, due-later mapping to `upcomingBody`, fixed-window behavior across a DST transition, and returned-loan exclusion in both consumers.
- Snapshot: active only, multiple loans of one item, soft-removed but active item, missing item/borrower, all entries unresolved, deterministic ties, series-cover fallback, missing series, and periodical/catalogue failures remaining failures.
- Catalogue reads: no active loans performs no query, duplicate item IDs are read once, missing IDs count unresolved, issue-detail mapping, sequential/bounded completion, and any storage `Left` fails the whole snapshot.
- Templates: Hindi and right-to-left round trips, required and repeated placeholders, unknown/unclosed/stray tokens, blank/over-limit input, no-due-date wording, body/final-length agreement, final-length refusal from a long title, and literal non-recursive substitution when a title contains placeholder-like text.
- Template store/controller: versioned round trip, wrong preference type, corrupt/newer/oversized JSON, excessive nesting, non-ASCII input proving the 64 KiB cap is UTF-8 bytes, selected-template deletion, unavailable selection, failed writes preserving prior state, and concurrent mutations serialized without lost updates.
- Preparation: correct status body and local date, exact caption, sanitized JPEG MIME/bytes at the unchanged publish rendition, safe filename, blank/remote text-only result, safe-local missing/corrupt/oversized refusal, streamed byte-cap enforcement, and proof that remote-only covers cause no fetch.

### Widget and integration tests

- Drawer opens Borrowed Items; locked/uninitialized routes work; vault-session loading/error, unlocked empty/error/retry, and all-unresolved states are distinct. Locking while visible removes stale titles/details/actions immediately.
- Cards show real title/cover/borrower/phone and separate entries for multiple copies; filters and minute-tick transitions update correctly. `ItemCover` receives `owner: null` and never requests materialization.
- Template CRUD, default selection, restart persistence, Unicode editing, validation messages, plaintext-storage guidance, and sample previews.
- WhatsApp tap passes the exact sanitized bytes, caption, MIME type, filename, and iPad origin to a fake `FileShareService`; duplicate taps collapse and busy state is isolated by loan ID.
- Dismissed/success/unavailable/throw outcomes produce the specified UI and never claim a message was sent. Returning from share with the global app lock enabled re-gates without `LockSuppressor`.
- Blank/remote text-only choice calls `shareText` explicitly; safe-local missing/corrupt/oversized covers and invalid templates never invoke the share service. Locking during asynchronous preparation aborts before hand-off.
- Call uses the sanitized dialer URI; missing phone hides Call without removing the loan card or its generic reminder-share action.
- Accessibility checks at 320 pixels, large text, dark theme, phone list and wide grid; useful button tooltips/semantics and no overflow.
- Add the message/date tests to the CI timezone matrix (`Asia/Calcutta` and `America/New_York`), including a local-midnight due date that must not shift through UTC formatting.

### Required project gates

- `dart run build_runner build --delete-conflicting-outputs` with no uncommitted generated diff.
- `dart analyze` with zero issues and `dart format --set-exit-if-changed lib test integration_test`.
- `flutter test --coverage --exclude-tags golden`, relevant golden tests, architecture/domain-purity checks, and the timezone matrix.
- Existing Rust gates remain green: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo deny check`, and `cargo test --release`.
- Dependency/secret/OSV scans and `fdroidReleaseRuntimeClasspath` purity check; no new dependency is expected.

### Manual device verification

- On a real Android device with WhatsApp, verify that one Pitak tap hands off the actual cover and caption together, the maintainer can choose a conversation/edit/cancel, and nothing sends until WhatsApp's Send button. This is a required verification before claiming the behavior, not an assumption from `ShareLibrarySheet`.
- Repeat with Hindi and a right-to-left template containing a Latin title, an overdue loan, due-soon and due-later loans, no due date, and a long caption. Record truncation/ordering exactly as received; do not add bidi isolate marks or claim an external caption limit from memory.
- Repeat with no cover, a remote-only cover, a missing/corrupt/oversized local cover, process restart after selecting a custom default, and return from WhatsApp with the global app lock enabled.
- With WhatsApp not installed, verify the generic sheet offers only available targets and that choosing another target or dismissing remains honest; the app must not report that it detected WhatsApp's absence.
- Verify the generic share flow on iOS/iPad if available, including popover anchoring. Caption presentation is controlled by the receiving app, so record platform-specific behavior rather than promising identical rendering everywhere.
- Smoke both Play and F-Droid flavors; no WhatsApp or Google code should be bundled.

## Decision points

### Settled design

- **Scope:** this plan includes the complete Borrowed Items page and reusable templates, not only the sharing helper.
- **One entry per active loan:** required for correct multi-copy behavior; card and busy identity is the loan ID.
- **Whole page vault-gated:** no borrowed-title list while locked or stale entries after a lock transition.
- **Existing time semantics:** keep overdue-from-local-midnight and the rolling 72-hour due-soon window. Changing to calendar-day or end-of-due-day behavior would require an explicit maintainer decision and changes to both pages.
- **Local instant dates:** loan due dates use the shared local `10 November 2026`-style formatter, never `CalendarDate`. All other user-visible dates use the same full-month display helper, with UTC calendar-day fields kept separate from local instants and storage/export/wire formats unchanged.
- **Catalogue reads:** sequential `getById` per unique item in v1; a measured later need may justify `getByIds` and its test updates.
- **Cross-platform share sheet first:** use the existing `share_plus` service. A targeted Android WhatsApp intent is a later optimization only if its extra native FileProvider/URI security work is justified.
- **Template model:** named custom Unicode templates with three status bodies and two placeholders; built-in English remains the safe initial default. Dated bodies require `{{dueDate}}`; repeated known placeholders are allowed.
- **Storage:** dedicated versioned preference JSON, not a Drift schema migration and not the encrypted Rust vault. Templates are device-local, plaintext, excluded from the current backup, and must not be described as incapable of containing private free text.
- **Cover recipe:** the shared reader uses the existing publish defaults and a streamed 8 MiB source cap; publishing behavior is not silently changed to a reminder-specific rendition.
- **No silent fallback:** no remote cover fetch, no raw image share, no hidden language switch, no fail-soft repository read, and no automatic text-only share after a corrupt cover.
- **Pending remains:** it keeps its current role; both pages share the same urgency classifier and local date formatter so they cannot disagree.

### Maintainer choices before implementation

- **Delivery:** implement one complete change in the recommended three internal stages: (a) urgency/read model/page with Call, (b) templates, (c) WhatsApp sharing.
- **V1 surface:** full scope, including responsive grid, template duplication, placeholder chips, and previews.
- **Dated-placeholder rule:** `{{dueDate}}` remains required in dated bodies, as specified in the approved plan.

## Out-of-scope observations

- Template backup/restore/export and synchronization across devices should be designed separately; preference-stored templates will not automatically travel with the current library backup.
- Additional placeholders (`borrowerName`, `libraryName`), localized month names, rich text, automatic translation, and per-borrower template overrides are deliberately deferred.
- A native Android direct-to-WhatsApp image intent could reduce one share-sheet step, but it needs a separate security review for content URIs, temporary-file lifetime, package visibility, and fallback behavior.
- Pending still shows `Item #id`; this plan does not rewrite it, although the new page becomes the richer loan-management destination.
- The existing size-unit limitation in `PrefsPublishHostStore` and fail-soft behavior in `periodicalCoversProvider` and Pending are not refactored by this feature. The new code avoids copying them where strict reads are required. The shared local-cover reader is in scope because both publishing and reminders will use its bounded implementation.

## Review record

- Reviewed against `58652ca` on `remoteImport`. The drawer, vault state, urgency/tick, contact, repository, cover, sharing, preference, CI-timezone, and ADR seams were verified directly.
- The revised approach incorporates the second review: local instant dates, rolling-72-hour wording, owner-less covers, bounded per-ID reads, strict periodical failures, streamed cover byte limits, typed cover outcomes, UTF-16/UTF-8 cap distinctions, JSON depth/type guards, `SerialOpQueue`, unresolved/lock edge states, plaintext-template honesty, share-cache behavior, and device-verified WhatsApp claims.
- The focused baseline is 92 passing tests under Flutter 3.44.2. No full-suite, Rust, release, or real-device verification has been performed for this proposed feature.

## Result

Implemented the full Borrowed Items destination, strict active-loan read model, responsive cards and filters, Unicode template CRUD/selection/persistence, bounded sanitized cover preparation, explicit generic OS sharing, and direct WhatsApp text with the borrower's sanitized phone number on the `reminders` branch. `main` was fast-forwarded from `4945b8f` to `58652ca` before the branch was created; the 1.9.4 plan is preserved at `docs/plans/release-1.9.4-aab.md`.

Verified under pinned Flutter 3.44.2:

- 6,013 non-golden tests passed with coverage (above the 64% floor), including direct WhatsApp number/caption launch with no cover read and bold title/date substitution.
- `dart analyze lib test`, formatting, `git diff --check`, and consecutive build_runner stability checks passed.
- Both CI timezone runs passed, including the new loan date/message tests.
- Rust `cargo fmt --check`, clippy with warnings denied, `cargo deny check`, and release tests passed (36 tests; 2 real-archive tests remain environment-gated).
- Secret scan and F-Droid purity plus Play positive control passed. No dependency was added.
- Golden tests were attempted on macOS and failed with the documented renderer differences; Linux CI remains the reference renderer. No golden PNG was changed.

Remaining verification: `osv-scanner` is not installed, so the pubspec OSV scan was not run (Rust advisories did run through `cargo deny`). The F-Droid release APK was built and installed on the Pixel 8a. Real Android WhatsApp cover/caption behavior, Hindi/RTL rendering, missing/corrupt/oversized covers, restart persistence, app-lock round trip, iOS/iPad behavior, and Play/F-Droid device smoke are still unverified. Test-install guidance now requires the F-Droid flavor and `adb install -r` in `README.md` and `docs/RELEASING.md`.
