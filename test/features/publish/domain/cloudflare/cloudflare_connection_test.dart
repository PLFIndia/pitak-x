import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';

import '../../support/cloudflare_fakes.dart';

void main() {
  test('manual proof for Worker A cannot confirm Worker B', () {
    final proven = cloudflareTestConnection(
      confirmed: false,
      writeConfirmed: true,
    );
    expect(proven.verifiedWorkerName?.value, 'pitak-library');

    final changed = proven.selectWorker(cloudflareTestWorker('other-worker'));
    expect(changed.status.addressConfirmed, isFalse);
    expect(changed.status.workersWriteConfirmed, isFalse);
    expect(changed.status.target, isNull);
    expect(
      changed.status.unverifiedAddress?.verificationSiteUrl,
      'https://other-worker.library.workers.dev/',
    );
  });

  test(
    'API-subdomain confirmation survives Worker change but write proof resets',
    () {
      final proven = cloudflareTestConnection(writeConfirmed: true);
      expect(proven.verifiedWorkerName, isNull);

      final changed = proven.selectWorker(cloudflareTestWorker('other-worker'));
      expect(changed.status.addressConfirmed, isTrue);
      expect(changed.status.workersWriteConfirmed, isFalse);
      expect(
        changed.status.target?.siteUrl,
        'https://other-worker.library.workers.dev/',
      );
    },
  );

  test('a forged proof/Worker mismatch is refused at the record boundary', () {
    final connection = CloudflareConnection.tryCreate(
      token: cloudflareTestToken(),
      accountId: cloudflareTestAccount(),
      accountSubdomain: cloudflareTestSubdomain(),
      workerName: cloudflareTestWorker('worker-a'),
      verifiedWorkerName: cloudflareTestWorker('worker-b'),
      addressConfirmed: true,
      workersWriteConfirmed: true,
    );
    expect(connection, isNull);
  });

  test('subdomain selection requires an account first', () {
    final connection = CloudflareConnection.verifiedToken(
      cloudflareTestToken(),
    );
    expect(
      () => connection.selectSubdomain(
        cloudflareTestSubdomain(),
        confirmed: true,
      ),
      throwsStateError,
    );
  });
}
