import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:libcompress/libcompress.dart';
import 'test_utils.dart';

void main() {
  group('Snappy CLI Compatibility - Decompress CLI-generated fixtures', () {
    for (final path in standardFixtures) {
      test('decompresses $path from snappy CLI', () {
        final codec = SnappyCodec();
        final original = readDataFixture(path);
        final compressed = readCodecFixture('snappy', '$path.snappy');
        final decompressed = codec.decompress(compressed);
        expect(decompressed, equals(original));
      });
    }
  });

  group('Snappy CLI Compatibility - Library output readable by CLI (snzip)', () {
    test('streaming format readable by snzip CLI', () async {
      if (!await cliAvailableCached('snzip')) {
        markTestSkipped('snzip CLI tool not available');
        return;
      }

      // snzip only supports framing format
      final codec = SnappyCodec(framing: true);
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_snappy_test.sz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'snzip',
          ['-d', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'snzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });

    test('small chunk size readable by snzip CLI', () async {
      if (!await cliAvailableCached('snzip')) {
        markTestSkipped('snzip CLI tool not available');
        return;
      }

      final codec = SnappyCodec(framing: true, chunkSize: 4096);
      final original = readDataFixture('canterbury/alice29.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_snappy_small.sz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'snzip',
          ['-d', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'snzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });
  });

  group('Snappy CLI Compatibility - Bidirectional round-trip', () {
    test('library compress -> CLI decompress -> CLI compress -> library decompress',
        () async {
      if (!await cliAvailableCached('snzip')) {
        markTestSkipped('snzip CLI tool not available');
        return;
      }

      final codec = SnappyCodec(framing: true);
      final original = readDataFixture('calgary/paper1');
      final libCompressed = codec.compress(original);

      final path = '/tmp/libcompress_snappy_bidir.sz';
      final out = '/tmp/libcompress_snappy_bidir.out';

      try {
        // Library -> CLI decompress
        await File(path).writeAsBytes(libCompressed);
        final result = await Process.run(
          'snzip',
          ['-d', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'snzip decompression failed: ${result.stderr}');
        final cliOut = result.stdout as List<int>;
        expect(cliOut, equals(original));

        // Write decompressed to file for re-compression
        await File(out).writeAsBytes(cliOut);

        // CLI compress -> Library decompress
        final result2 = await Process.run(
          'snzip',
          ['-c', out],
          stdoutEncoding: null,
        );
        expect(result2.exitCode, 0,
            reason: 'snzip compression failed: ${result2.stderr}');
        final cliCompressed = result2.stdout as List<int>;
        final libOut = codec.decompress(Uint8List.fromList(cliCompressed));
        expect(libOut, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });
  });

  group('Snappy CLI Compatibility - All fixtures round-trip', () {
    for (final path in standardFixtures) {
      test('full round-trip for $path', () async {
        if (!await cliAvailableCached('snzip')) {
          markTestSkipped('snzip CLI tool not available');
          return;
        }

        final codec = SnappyCodec(framing: true);
        final original = readDataFixture(path);
        final libCompressed = codec.compress(original);

        final tmpPath =
            '/tmp/libcompress_snappy_rt_${path.replaceAll('/', '_')}.sz';

        try {
          await File(tmpPath).writeAsBytes(libCompressed);
          final result = await Process.run(
            'snzip',
            ['-d', '-c', tmpPath],
            stdoutEncoding: null,
          );
          expect(result.exitCode, 0,
              reason: 'CLI decompression failed for $path');
          final cliOut = result.stdout as List<int>;
          expect(cliOut, equals(original),
              reason: 'Round-trip mismatch for $path');
        } finally {
          await cleanup([tmpPath]);
        }
      });
    }
  });

  group('Snappy edge cases', () {
    test('compresses and decompresses empty data', () {
      final codec = SnappyCodec();
      final empty = Uint8List(0);
      final compressed = codec.compress(empty);
      expect(compressed.length, 1); // Just the varint 0
      expect(compressed[0], 0);
      final decompressed = codec.decompress(compressed);
      expect(decompressed.length, 0);
    });

    test('compresses and decompresses single byte', () {
      final codec = SnappyCodec();
      final data = Uint8List.fromList([42]);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, orderedEquals(data));
    });

    test('compresses and decompresses highly compressible data', () {
      final codec = SnappyCodec();
      final data = Uint8List.fromList(List.filled(10000, 65)); // All 'A's
      final compressed = codec.compress(data);
      expect(compressed.length, lessThan(data.length ~/ 2));
      final decompressed = codec.decompress(compressed);
      expect(decompressed, orderedEquals(data));
    });
  });
}
