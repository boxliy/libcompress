import 'dart:io';
import 'dart:typed_data';

/// Check if a CLI tool is available on the system
///
/// Returns true if the tool can be executed, false otherwise.
/// This allows tests to skip gracefully when CLI tools aren't installed.
Future<bool> cliAvailable(final String tool) async {
  try {
    final result = await Process.run(tool, ['--version']);
    // Most tools return 0 on --version, some return 1
    return result.exitCode == 0 || result.exitCode == 1;
  } catch (_) {
    return false;
  }
}

/// Cache for CLI availability to avoid repeated checks
final Map<String, bool> _cliCache = {};

/// Check CLI availability with caching
Future<bool> cliAvailableCached(final String tool) async {
  if (_cliCache.containsKey(tool)) {
    return _cliCache[tool]!;
  }
  final available = await cliAvailable(tool);
  _cliCache[tool] = available;
  return available;
}

/// Read a fixture file as bytes
Uint8List readFixture(final String path) {
  return Uint8List.fromList(File(path).readAsBytesSync());
}

/// Read a data fixture (test/fixtures/data/...)
Uint8List readDataFixture(final String name) {
  return readFixture('test/fixtures/data/$name');
}

/// Read a codec fixture (test/fixtures/{codec}/...)
Uint8List readCodecFixture(final String codec, final String name) {
  return readFixture('test/fixtures/$codec/$name');
}

/// Standard fixture paths for testing
const standardFixtures = <String>[
  'empty.txt',
  'zeros.bin',
  'random.bin',
  'html',
  'artificial/aaa.txt',
  'artificial/alphabet.txt',
  'canterbury/alice29.txt',
  'calgary/paper1',
];

/// Clean up temporary test files
Future<void> cleanup(final List<String> paths) async {
  for (final path in paths) {
    try {
      await File(path).delete();
    } catch (_) {
      // Ignore errors on cleanup
    }
  }
}
