/// Secret-free state and prompt descriptions for Cloudflare connection UI.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Whether the controller is idle, doing IO, or waiting outside the queue.
enum CloudflareConnectionPhase {
  /// No operation is running.
  idle,

  /// An API or storage command is running inside the queue.
  working,

  /// A dialog is open; the publish queue is not held.
  awaitingInput,

  /// The stored connection exists but cannot be decoded (an older app version
  /// or a reset secure store). It carries no secret; the user can forget it
  /// without losing the public site, Worker or share link (fix-plan M7).
  unreadable,
}

/// Every dialog the setup state machine can request.
enum CloudflareSetupPrompt {
  /// Paste a new API token.
  token,

  /// Choose a listed account or the manual-ID path.
  account,

  /// Enter an Account ID manually.
  manualAccount,

  /// Consent to and name a new account subdomain.
  createSubdomain,

  /// Enter an existing subdomain as an unverified candidate.
  manualSubdomain,

  /// Choose the dedicated Worker name.
  worker,

  /// Consent to replace every asset on an existing Worker.
  workerReplacement,

  /// Consent to the marker-only verification deployment.
  verification,
}

/// The account picker's answer: a listed account or the manual-ID path.
final class CloudflareAccountChoice {
  /// Creates a listed-account choice, or a manual choice when [manual] is true.
  const CloudflareAccountChoice({this.account, this.manual = false});

  /// The listed account, or null for the manual-ID path.
  final CloudflareAccount? account;

  /// True when the user chose manual Account ID entry.
  final bool manual;
}

/// Immutable presentation state. No token, JWT, or authorization value exists
/// in this object or in any type it references.
final class CloudflareConnectionUi {
  /// Creates UI state.
  const CloudflareConnectionUi({
    this.phase = CloudflareConnectionPhase.idle,
    this.status = CloudflareConnectionStatus.empty,
    this.activeHost,
    this.prompt,
    this.promptSerial = 0,
    this.promptInitialValue,
    this.promptWorkerExists = false,
    this.promptVerificationRequested = false,
    this.accounts = const [],
    this.statusMessage,
  });

  /// Current operation phase; dialogs are enabled only for their prompt.
  final CloudflareConnectionPhase phase;

  /// Safe connection projection; no token or JWT is present.
  final CloudflareConnectionStatus status;

  /// Journal fact only; it is not inferred from credentials or a deploy.
  final PublishHost? activeHost;

  /// Non-null while the page should show one dialog.
  final CloudflareSetupPrompt? prompt;

  /// Monotonically increasing id; answers from an older dialog are refused.
  final int promptSerial;

  /// Optional previous/rejected input shown by a name dialog.
  final String? promptInitialValue;

  /// Whether the Worker existed during the latest remote check.
  final bool promptWorkerExists;

  /// Whether replacement consent should resume manual-address verification.
  final bool promptVerificationRequested;

  /// Bounded account choices shown only by the account prompt.
  final List<CloudflareAccount> accounts;

  /// Fixed application-owned copy only.
  final String? statusMessage;

  /// Creates a modified copy, using a sentinel for nullable-field clearing.
  CloudflareConnectionUi copyWith({
    CloudflareConnectionPhase? phase,
    CloudflareConnectionStatus? status,
    Object? activeHost = _keep,
    Object? prompt = _keep,
    int? promptSerial,
    Object? promptInitialValue = _keep,
    bool? promptWorkerExists,
    bool? promptVerificationRequested,
    List<CloudflareAccount>? accounts,
    Object? statusMessage = _keep,
  }) => CloudflareConnectionUi(
    phase: phase ?? this.phase,
    status: status ?? this.status,
    activeHost: identical(activeHost, _keep)
        ? this.activeHost
        : activeHost as PublishHost?,
    prompt: identical(prompt, _keep)
        ? this.prompt
        : prompt as CloudflareSetupPrompt?,
    promptSerial: promptSerial ?? this.promptSerial,
    promptInitialValue: identical(promptInitialValue, _keep)
        ? this.promptInitialValue
        : promptInitialValue as String?,
    promptWorkerExists: promptWorkerExists ?? this.promptWorkerExists,
    promptVerificationRequested:
        promptVerificationRequested ?? this.promptVerificationRequested,
    accounts: accounts ?? this.accounts,
    statusMessage: identical(statusMessage, _keep)
        ? this.statusMessage
        : statusMessage as String?,
  );
}

const Object _keep = Object();
