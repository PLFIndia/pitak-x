/// Staged Cloudflare connection/setup commands (D.2/F.2).
///
/// The outer controller holds the app-wide queue for each command, releases it
/// while a dialog is open, and re-enters for the next command. Methods re-read
/// the whole record after that re-entry; no nested queue is used.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_operation_attempt.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_constraint.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_setup_journal.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_account.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/application/cloudflare/verify_cloudflare_address.dart';
import 'package:pitaka/features/publish/application/site/pending_move_target_guard.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Account, subdomain, Worker, verification, and finalization orchestration.
final class SetupCloudflareSite {
  /// Creates the use case over narrow ports.
  const SetupCloudflareSite({
    required CloudflareAccountApi accountApi,
    required CloudflareDeployApi deployApi,
    required CloudflareCredentialStore credentials,
    required PublishHostStateRepository hostState,
    required VerifyCloudflareAddress verifyAddress,
    required int Function() clock,
  }) : _accountApi = accountApi,
       _deployApi = deployApi,
       _credentials = credentials,
       _hostState = hostState,
       _verifyAddress = verifyAddress,
       _clock = clock;

  final CloudflareAccountApi _accountApi;
  final CloudflareDeployApi _deployApi;
  final CloudflareCredentialStore _credentials;
  final PublishHostStateRepository _hostState;
  final VerifyCloudflareAddress _verifyAddress;
  final int Function() _clock;

  /// Subdomain commands over the same ports; cheap to build per call.
  CloudflareSubdomainCommands get _subdomains => CloudflareSubdomainCommands(
    accountApi: _accountApi,
    credentials: _credentials,
  );

  /// Loads only the secret-free projection for controller state.
  Future<Either<Failure, CloudflareConnectionStatus>> loadStatus() =>
      _attempt(() async {
        final loaded = await _credentials.read();
        return switch (loaded) {
          Left(value: final failure) => left(failure),
          Right(value: final connection) => right(
            connection?.status ?? CloudflareConnectionStatus.empty,
          ),
        };
      });

  /// Non-migrating current host read; setup never infers a live share address.
  PublishHost? currentActiveHost() => _hostState.currentState()?.activeHost;

  /// The exact address the journal already proved, for prompt prefill.
  ///
  /// A pending move's Cloudflare endpoint wins over the verified target,
  /// because that is the address the user must reconnect to (fix-plan M5).
  CloudflareSetupHint? setupHint() => _journal.hint();

  /// Starts a NEW connection. A user token is verified but NOT saved yet; the
  /// whole record is written at [selectAccount], exactly like an account token.
  ///
  /// Why (fix-plan M3): saving at token entry replaced the working connection
  /// immediately, so abandoning setup halfway left the user with a fresh,
  /// incomplete record and no way back to the old one.
  Future<Either<Failure, CloudflareAccountDiscovery>> begin(
    CloudflareApiToken token,
  ) => _attempt(() async {
    if (token.kind == CloudflareApiTokenKind.user) {
      // The legacy 40-character shape deliberately takes this same user route;
      // there is no undocumented fallback to the account endpoint.
      final verification = await _accountApi.verifyUserToken(token);
      final inactive = cloudflareTokenInactive(verification, _clock());
      if (inactive) {
        return left(
          const CloudflareFailure(CloudflareErrorMessages.inactiveToken),
        );
      }
      return discoverCloudflareAccounts(
        _accountApi,
        token,
        tokenExpiresOn: verification.expiresOn,
      );
    }
    return discoverCloudflareAccounts(_accountApi, token);
  });

  /// Resumes account discovery with an already verified stored token.
  Future<Either<Failure, CloudflareAccountDiscovery>> discoverAccounts() =>
      _withRecord(
        (connection) => connection.useToken(
          (token) => discoverCloudflareAccounts(_accountApi, token),
        ),
      );

  /// Validates and selects a manually entered Account ID.
  Future<Either<Failure, CloudflareSubdomainOutcome>> selectAccountId(
    String raw, {
    CloudflareApiToken? pendingToken,
    DateTime? tokenExpiresOn,
  }) async {
    final accountId = CloudflareAccountId.tryParse(raw);
    if (accountId == null) {
      return left<Failure, CloudflareSubdomainOutcome>(
        const ValidationFailure(CloudflareErrorMessages.invalidAccount),
      );
    }
    return selectAccount(
      accountId: accountId,
      accountName: null,
      pendingToken: pendingToken,
      tokenExpiresOn: tokenExpiresOn,
    );
  }

  /// Selects an account, verifies an account-owned token if necessary, stores
  /// the complete record, then reads its account subdomain.
  Future<Either<Failure, CloudflareSubdomainOutcome>> selectAccount({
    required CloudflareAccountId accountId,
    required String? accountName,
    CloudflareApiToken? pendingToken,
    DateTime? tokenExpiresOn,
  }) async {
    if (!CloudflareConnection.isValidAccountName(accountName)) {
      return left<Failure, CloudflareSubdomainOutcome>(
        CloudflareFailure(CloudflareApiExceptionKind.malformedResponse.message),
      );
    }
    final constrained = _checkConstraint(
      (constraint) => constraint.allowsAccount(accountId),
    );
    if (constrained case Left(value: final failure)) {
      return left<Failure, CloudflareSubdomainOutcome>(failure);
    }
    final token = pendingToken;
    if (token != null) {
      return _attempt(() async {
        final CloudflareConnection selected;
        if (token.kind == CloudflareApiTokenKind.account) {
          final verification = await _accountApi.verifyAccountToken(
            token: token,
            accountId: accountId,
          );
          if (cloudflareTokenInactive(verification, _clock())) {
            return left(
              const CloudflareFailure(CloudflareErrorMessages.inactiveToken),
            );
          }
          selected = CloudflareConnection.verifiedToken(
            token,
            tokenExpiresOn: verification.expiresOn,
          ).selectAccount(id: accountId, name: accountName);
        } else {
          // A user token was verified in `begin`; its expiry came with the
          // listing, so no second verify call is needed.
          selected = CloudflareConnection.verifiedToken(
            token,
            tokenExpiresOn: tokenExpiresOn,
          ).selectAccount(id: accountId, name: accountName);
        }
        return _completeAccountSelection(selected);
      });
    }
    return _withRecord(
      (current) => _completeAccountSelection(
        current.selectAccount(id: accountId, name: accountName),
      ),
    );
  }

  /// Re-reads the subdomain when setup resumes after account selection.
  Future<Either<Failure, CloudflareSubdomainOutcome>> readSubdomain() =>
      _withRecord(_readSubdomain);

  /// Explicitly creates a missing account subdomain after availability proof.
  Future<Either<Failure, CloudflareSubdomainOutcome>> createSubdomain(
    String raw,
  ) => _withRecord((current) {
    final constrained = _checkSubdomain(raw);
    if (constrained case Left(value: final failure)) {
      return Future.value(left<Failure, CloudflareSubdomainOutcome>(failure));
    }
    return _subdomains.create(current, raw);
  });

  /// Stores a manual candidate only. It cannot become a target before F.2.
  Future<Either<Failure, CloudflareSubdomainOutcome>> useManualSubdomain(
    String raw,
  ) => _withRecord((current) {
    final constrained = _checkSubdomain(raw);
    if (constrained case Left(value: final failure)) {
      return Future.value(left<Failure, CloudflareSubdomainOutcome>(failure));
    }
    return _subdomains.useManual(current, raw);
  });

  /// Checks a Worker and either requests consent/verification or finalizes.
  Future<Either<Failure, CloudflareWorkerOutcome>> selectWorker(
    String raw, {
    bool replacementConsent = false,
    bool verificationConfirmed = false,
  }) => _withRecord((current) async {
    final accountId = current.accountId;
    final subdomain = current.accountSubdomain;
    if (accountId == null || subdomain == null) {
      return left(
        const CloudflareFailure(CloudflareErrorMessages.subdomainRequired),
      );
    }
    final worker = CloudflareWorkerName.tryParse(raw);
    if (worker == null) {
      return left(
        const ValidationFailure(CloudflareErrorMessages.invalidWorker),
      );
    }
    final constrained = _checkConstraint(
      (constraint) => constraint.allowsWorker(worker),
    );
    if (constrained case Left(value: final failure)) {
      return left<Failure, CloudflareWorkerOutcome>(failure);
    }
    final exists = await current.useToken(
      (token) => _deployApi.workerExists(
        token: token,
        accountId: accountId,
        workerName: worker,
      ),
    );
    final selected = current.selectWorker(worker); // Prospective record only.
    if (selected.addressConfirmed) {
      if (exists && !replacementConsent) {
        return right(
          CloudflareWorkerReplacementRequired(
            workerName: worker,
            verificationRequested: false,
          ),
        );
      }
      return _finalize(selected);
    }

    // M3: the prospective target is already the address this phone proved
    // live (the journal's verified target, or a pending move's destination).
    // That read-back IS the address proof, so finalize WITHOUT the destructive
    // marker-only deploy. Write access is still unproven.
    if (exists && _isProvenAddress(selected)) {
      return _finalize(selected.markAddressProven());
    }

    if (!verificationConfirmed) {
      return right(
        CloudflareVerificationRequired(
          workerName: worker,
          workerExists: exists,
          isActiveSite: _isActiveSite(selected),
        ),
      );
    }
    if (exists && !replacementConsent) {
      return right(
        CloudflareWorkerReplacementRequired(
          workerName: worker,
          verificationRequested: true,
        ),
      );
    }

    // Persist the exact candidate BEFORE the first remote write. A crash can
    // therefore resume verification instead of forgetting which Worker may
    // contain a marker. This is still not a confirmed publish target.
    final candidate = selected;
    final saved = await _credentials.save(candidate);
    if (saved case Left(value: final failure)) return left(failure);
    final verified = await candidate.useToken(
      (token) => _verifyAddress.call(
        token: token,
        accountId: accountId,
        workerName: worker,
        subdomain: subdomain,
        workerExists: exists,
      ),
    );
    switch (verified) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: final target):
        final confirmed = candidate.markVerificationReadBack();
        if (confirmed.status.target?.targetId != target.targetId) {
          return left(const CloudflareFailure(CloudflareErrorMessages.generic));
        }
        return _finalize(confirmed, remoteVerificationSucceeded: true);
    }
  });

  /// Retries ONLY final host activation after a previous local partial failure.
  /// No upload or deployment is performed by this command.
  Future<Either<Failure, CloudflareWorkerOutcome>> finishSetup() =>
      _withRecord((current) async {
        final status = current.status;
        final target = status.target;
        if (target == null) {
          return left(
            const CloudflareFailure(CloudflareErrorMessages.connectionRequired),
          );
        }
        final allowed = _allowTarget(target);
        if (allowed case Left(value: final failure)) return left(failure);
        final activated = await _hostState.ensureActiveHost(
          PublishHost.cloudflare,
        );
        if (activated case Left()) {
          return left(
            const CloudflareFailure(CloudflareErrorMessages.hostActivation),
          );
        }
        return right(
          CloudflareWorkerReady(
            target: target,
            workersWriteConfirmed: status.workersWriteConfirmed,
          ),
        );
      });

  /// Forgets only the secure connection; public state and the Worker survive.
  Future<Either<Failure, Unit>> disconnect() => _credentials.clear();

  Either<Failure, Unit> _allowTarget(CloudflarePublishTarget target) =>
      PendingMoveTargetGuard(_hostState).allows(target);

  /// The journal-derived rules (constraint, proven address, prefill).
  CloudflareSetupJournal get _journal => CloudflareSetupJournal(_hostState);

  Either<Failure, Unit> _checkConstraint(
    bool Function(CloudflareSetupConstraint constraint) rule,
  ) => _journal.check(rule);

  Either<Failure, Unit> _checkSubdomain(String raw) =>
      _journal.checkSubdomain(raw);

  bool _isProvenAddress(CloudflareConnection connection) =>
      _journal.isProvenAddress(connection);

  bool _isActiveSite(CloudflareConnection connection) =>
      _journal.isActiveSite(connection);

  Future<Either<Failure, CloudflareSubdomainOutcome>> _completeAccountSelection(
    CloudflareConnection selected,
  ) async {
    final saved = await _credentials.save(selected);
    if (saved case Left(value: final failure)) return left(failure);
    return _readSubdomain(selected);
  }

  Future<Either<Failure, CloudflareSubdomainOutcome>> _readSubdomain(
    CloudflareConnection current,
  ) => _subdomains.read(current);

  Future<Either<Failure, CloudflareWorkerOutcome>> _finalize(
    CloudflareConnection connection, {
    bool remoteVerificationSucceeded = false,
  }) async {
    final status = connection.status;
    final target = status.target;
    if (target == null) {
      return left(const CloudflareFailure(CloudflareErrorMessages.generic));
    }
    final allowed = _allowTarget(target);
    if (allowed case Left(value: final failure)) return left(failure);
    // Confirmed target first; only then may the journal select a host.
    final saved = await _credentials.save(connection);
    if (saved case Left(value: final failure)) {
      if (remoteVerificationSucceeded) {
        return left(
          const CloudflareFailure(
            CloudflareErrorMessages.remoteVerifiedLocalSaveFailed,
          ),
        );
      }
      return left(failure);
    }
    final activated = await _hostState.ensureActiveHost(PublishHost.cloudflare);
    if (activated case Left()) {
      return left(
        const CloudflareFailure(CloudflareErrorMessages.hostActivation),
      );
    }
    return right(
      CloudflareWorkerReady(
        target: target,
        workersWriteConfirmed: status.workersWriteConfirmed,
      ),
    );
  }

  Future<Either<Failure, T>> _withRecord<T>(
    Future<Either<Failure, T>> Function(CloudflareConnection) action,
  ) => _attempt(() async {
    final loaded = await _credentials.read();
    switch (loaded) {
      case Left(value: final failure):
        return left(failure);
      case Right(value: final connection):
        if (connection == null) {
          return left(
            const CloudflareFailure(CloudflareErrorMessages.connectionRequired),
          );
        }
        return action(connection);
    }
  });

  Future<Either<Failure, T>> _attempt<T>(
    Future<Either<Failure, T>> Function() action,
  ) => attemptCloudflareSetup(action);
}
