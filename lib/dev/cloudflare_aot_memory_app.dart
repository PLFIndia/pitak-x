/// Android AOT runner for the S8 Cloudflare memory scenario.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:pitaka/dev/cloudflare_memory_scenario.dart';

const _outputPath = String.fromEnvironment(
  'S8_MEMORY_OUTPUT',
  defaultValue:
      '/data/user/0/dev.khoj.pitaka.fdroid/app_flutter/pitaka_s8_memory.json',
);

/// Runs the memory harness. Called by `lib/main_dev_harness.dart`, which is
/// the ONLY entry point that may reference this library (fix-plan L15).
void runCloudflareMemoryApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _MemoryApp());
}

final class _MemoryApp extends StatefulWidget {
  const _MemoryApp();

  @override
  State<_MemoryApp> createState() => _MemoryAppState();
}

final class _MemoryAppState extends State<_MemoryApp> {
  String _resultText = 'running';

  @override
  void initState() {
    super.initState();
    unawaited(_runProfile());
  }

  Future<void> _runProfile() async {
    try {
      await _writeResult('{"stage":"main"}');
      final result = await runCloudflareMemoryScenario();
      if (!mounted) return;
      final json = jsonEncode(result.toJson());
      setState(() => _resultText = json);
      await _writeResult(json);
    } on Object catch (error) {
      final json = jsonEncode({'error': error.toString()});
      if (mounted) setState(() => _resultText = json);
      await _writeResult(json);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Text(_resultText, key: const Key('memoryResult')),
          ),
        ),
      ),
    );
  }
}

Future<void> _writeResult(String json) async {
  final output = File(_outputPath);
  await output.create(recursive: true);
  await output.writeAsString(json, flush: true);
}
