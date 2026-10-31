/// An exact publish destination (publish domain, pure Dart; Cloudflare plan
/// R1/C3).
///
/// Why sealed (beginner note): a publish must never be pointed at "whatever
/// host and URL happen to be current". A move publishes the NEW target while
/// the old one is still active, and a retirement writes to the OLD one, so the
/// address must travel WITH the operation. The only way to build a target is
/// through the host's factory, which derives the canonical site URL from
/// validated parts — there is deliberately NO constructor that accepts an
/// arbitrary host + URL pair, so "publish to https://evil.example/" cannot be
/// expressed at all.
///
/// A target never contains a token. `library.json.siteUrl`, the read-back
/// origin and the journal's target record all come from the target passed to
/// the current operation, never from a global "active host" provider.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_url.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// The sealed base of every publish destination.
sealed class PublishTarget {
  const PublishTarget();

  /// Canonical public root of the site (always ends in `/`), derived from the
  /// validated parts — never supplied by a caller.
  String get siteUrl;

  /// Which host serves this site (`github` | `cloudflare`).
  PublishHost get host;

  /// Stable identity of this destination, persisted in the host journal and
  /// the manifest. No token, no ephemeral id.
  String get targetId;
}

/// Exact operation-endpoint comparison: API identity AND canonical address.
/// Cloudflare deliberately keeps [targetId] independent of its subdomain, so a
/// move/journal must check both rather than treating a changed address as the
/// same verified site.
extension PublishTargetExactMatch on PublishTarget {
  /// True only when [other] is the same identity at the same public address.
  bool isSameExactTarget(PublishTarget other) =>
      targetId == other.targetId && siteUrl == other.siteUrl;
}

/// A GitHub Pages destination (`owner/repo`, served from the branch Pages
/// serves).
final class GitHubPublishTarget extends PublishTarget {
  const GitHubPublishTarget._({
    required this.ownerRepo,
    required this.owner,
    required this.repo,
    required this.siteUrl,
  });

  /// Builds the target for [ownerRepo], or null when it is not a valid
  /// `owner/repo` pair.
  ///
  /// Validation IS the address derivation ([githubPagesUrlFor]): one rule set,
  /// so a target can never exist without a site URL that matches it. A null
  /// here is the "pick a target repo first" case, not an error to report.
  static GitHubPublishTarget? create(String? ownerRepo) {
    final siteUrl = githubPagesUrlFor(ownerRepo);
    if (siteUrl == null) return null;
    final parts = ownerRepo!.split('/');
    return GitHubPublishTarget._(
      ownerRepo: ownerRepo,
      owner: parts[0],
      repo: parts[1],
      siteUrl: siteUrl,
    );
  }

  /// The `owner/repo` string exactly as stored (the API-call identity).
  final String ownerRepo;

  /// Repository owner (a GitHub login).
  final String owner;

  /// Repository name.
  final String repo;

  @override
  final String siteUrl;

  @override
  PublishHost get host => PublishHost.github;

  @override
  String get targetId => 'github:$ownerRepo';

  /// Identity comparison WITHOUT overriding `==`/`hashCode`: the repo's lint
  /// bar refuses value equality on domain classes the analyzer cannot prove
  /// immutable (no `@immutable` in the pure domain, N14). `targetId` is the
  /// canonical identity, so two targets are the same when it matches.
  bool isSameTarget(PublishTarget other) => other.targetId == targetId;

  @override
  String toString() => 'GitHubPublishTarget($ownerRepo)';
}

/// A Cloudflare Workers destination: one account, one dedicated Worker.
///
/// The address is DERIVED from the three identity parts (account id, Worker
/// name, account subdomain) — there is no constructor that takes a URL, so a
/// target can never name a site its parts do not describe (C3/R15). The Worker
/// is dedicated to Pitak (C1/R12): a deploy replaces its complete asset set.
final class CloudflarePublishTarget extends PublishTarget {
  const CloudflarePublishTarget._({
    required this.accountId,
    required this.workerName,
    required this.accountSubdomain,
    required this.siteUrl,
  });

  /// Builds the target from its identity parts, or null when any is invalid.
  ///
  /// [workerName] is the API name (case preserved); the address uses its
  /// lower-case DNS label. A null here is the "finish Cloudflare setup" case,
  /// not an error to report.
  static CloudflarePublishTarget? create({
    required String? accountId,
    required String? workerName,
    required String? accountSubdomain,
  }) {
    final account = CloudflareAccountId.tryParse(accountId);
    final worker = CloudflareWorkerName.tryParse(workerName);
    final subdomain = CloudflareSubdomain.tryParse(accountSubdomain);
    if (account == null || worker == null || subdomain == null) return null;
    final site = CloudflareSiteUrl.create(
      workerName: worker.value,
      accountSubdomain: subdomain.value,
    );
    if (site == null) return null;
    return CloudflarePublishTarget._(
      accountId: account,
      workerName: worker,
      accountSubdomain: subdomain,
      siteUrl: site.siteUrl,
    );
  }

  /// The account the Worker lives in.
  final CloudflareAccountId accountId;

  /// The Worker's API name (case preserved).
  final CloudflareWorkerName workerName;

  /// The account-wide `workers.dev` subdomain.
  final CloudflareSubdomain accountSubdomain;

  @override
  final String siteUrl;

  @override
  PublishHost get host => PublishHost.cloudflare;

  /// Identity is the account plus the Worker name — the two things an API call
  /// needs. The subdomain is part of the ADDRESS, not of the Worker's identity:
  /// an account subdomain change makes the site unreachable (a typed
  /// `SiteUnavailable`), not a different Worker.
  @override
  String get targetId => 'cloudflare:${accountId.value}:${workerName.value}';

  /// Identity comparison without overriding `==`/`hashCode` (see
  /// [GitHubPublishTarget.isSameTarget]).
  bool isSameTarget(PublishTarget other) => other.targetId == targetId;

  @override
  String toString() => 'CloudflarePublishTarget($siteUrl)';
}
