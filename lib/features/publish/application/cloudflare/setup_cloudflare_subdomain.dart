/// Account-subdomain commands for Cloudflare setup (D.2/F.2).
///
/// Extracted from `setup_cloudflare_site.dart` (fix-plan Phase 0.4) so the
/// orchestrator stays under the size ratchet and these commands can grow.
/// Each function takes the already re-read connection record, so it never
/// caches a secret and never re-enters the app-wide queue.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';

/// Reads, creates and stores an account subdomain candidate.
final class CloudflareSubdomainCommands {
  /// Creates the commands over the account API and the secure record.
  const CloudflareSubdomainCommands({
    required CloudflareAccountApi accountApi,
    required CloudflareCredentialStore credentials,
  }) : _accountApi = accountApi,
       _credentials = credentials;

  final CloudflareAccountApi _accountApi;
  final CloudflareCredentialStore _credentials;

  /// Re-reads the subdomain when setup resumes after account selection.
  Future<Either<Failure, CloudflareSubdomainOutcome>> read(
    CloudflareConnection current,
  ) async {
    final accountId = current.accountId;
    if (accountId == null) {
      return left(
        const CloudflareFailure(CloudflareErrorMessages.accountRequired),
      );
    }
    final stored = current.accountSubdomain;
    if (stored != null) {
      return right(
        CloudflareSubdomainOutcome(
          current.addressConfirmed
              ? CloudflareSubdomainStep.confirmed
              : CloudflareSubdomainStep.candidate,
          stored,
        ),
      );
    }
    try {
      final subdomain = await current.useToken(
        (token) => _accountApi.readAccountSubdomain(
          token: token,
          accountId: accountId,
        ),
      );
      if (subdomain == null) {
        return right(
          const CloudflareSubdomainOutcome(
            CloudflareSubdomainStep.createRequired,
          ),
        );
      }
      final selected = current.selectSubdomain(subdomain, confirmed: true);
      final saved = await _credentials.save(selected);
      if (saved case Left(value: final failure)) return left(failure);
      return right(
        CloudflareSubdomainOutcome(
          CloudflareSubdomainStep.confirmed,
          subdomain,
        ),
      );
    } on CloudflareApiException catch (error) {
      if (error.kind == CloudflareApiExceptionKind.forbidden) {
        return right(
          const CloudflareSubdomainOutcome(
            CloudflareSubdomainStep.manualRequired,
          ),
        );
      }
      rethrow;
    }
  }

  /// Explicitly creates a missing account subdomain after availability proof.
  Future<Either<Failure, CloudflareSubdomainOutcome>> create(
    CloudflareConnection current,
    String raw,
  ) async {
    final accountId = current.accountId;
    if (accountId == null) {
      return left(
        const CloudflareFailure(CloudflareErrorMessages.accountRequired),
      );
    }
    final existing = current.accountSubdomain;
    if (existing != null && current.addressConfirmed) {
      return right(
        CloudflareSubdomainOutcome(CloudflareSubdomainStep.confirmed, existing),
      );
    }
    final candidate = CloudflareSubdomain.tryParse(raw);
    if (candidate == null) {
      return left(
        const ValidationFailure(CloudflareErrorMessages.invalidSubdomain),
      );
    }
    try {
      final checked = await current.useToken(
        (token) => _accountApi.checkAccountSubdomain(
          token: token,
          accountId: accountId,
          candidate: candidate,
        ),
      );
      switch (checked.availability) {
        case CloudflareSubdomainAvailability.taken:
          return left(
            const ValidationFailure(CloudflareErrorMessages.subdomainTaken),
          );
        case CloudflareSubdomainAvailability.unknown:
          return left(
            const CloudflareFailure(CloudflareErrorMessages.subdomainUnknown),
          );
        case CloudflareSubdomainAvailability.available:
          break;
      }
      final confirmed = await current.useToken(
        (token) => _accountApi.createAccountSubdomain(
          token: token,
          accountId: accountId,
          candidate: candidate,
        ),
      );
      final selected = current.selectSubdomain(confirmed, confirmed: true);
      final saved = await _credentials.save(selected);
      if (saved case Left(value: final failure)) return left(failure);
      return right(
        CloudflareSubdomainOutcome(
          CloudflareSubdomainStep.confirmed,
          confirmed,
        ),
      );
    } on CloudflareApiException catch (error) {
      if (error.kind == CloudflareApiExceptionKind.forbidden) {
        return right(
          const CloudflareSubdomainOutcome(
            CloudflareSubdomainStep.manualRequired,
          ),
        );
      }
      rethrow;
    }
  }

  /// Stores a manual candidate only. It cannot become a target before F.2.
  Future<Either<Failure, CloudflareSubdomainOutcome>> useManual(
    CloudflareConnection current,
    String raw,
  ) async {
    if (current.accountId == null) {
      return left(
        const CloudflareFailure(CloudflareErrorMessages.accountRequired),
      );
    }
    final candidate = CloudflareSubdomain.tryParse(raw);
    if (candidate == null) {
      return left(
        const ValidationFailure(CloudflareErrorMessages.invalidSubdomain),
      );
    }
    if (current.addressConfirmed &&
        current.accountSubdomain?.value == candidate.value) {
      return right(
        CloudflareSubdomainOutcome(
          CloudflareSubdomainStep.confirmed,
          candidate,
        ),
      );
    }
    final selected = current.selectSubdomain(candidate, confirmed: false);
    final saved = await _credentials.save(selected);
    if (saved case Left(value: final failure)) return left(failure);
    return right(
      CloudflareSubdomainOutcome(CloudflareSubdomainStep.candidate, candidate),
    );
  }
}
