import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:libcompress/libcompress.dart';
import 'test_utils.dart';

void main() {
  group('GZIP CLI Compatibility - Decompress CLI-generated fixtures', () {
    for (final path in standardFixtures) {
      test('decompresses $path from gzip CLI', () {
        final codec = GzipCodec();
        final original = readDataFixture(path);
        final compressed = readCodecFixture('gzip', '$path.gz');
        final decompressed = codec.decompress(compressed);
        expect(decompressed, equals(original));
      });
    }
  });

  group('GZIP CLI Compatibility - Library output readable by CLI', () {
    test('default level output readable by gzip CLI', () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec();
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_gzip_test.gz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'gzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });

    test('level 1 (fast) output readable by gzip CLI', () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec(level: 1);
      final original = readDataFixture('canterbury/alice29.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_gzip_fast.gz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'gzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });

    test('level 9 (best) output readable by gzip CLI', () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec(level: 9);
      final original = readDataFixture('canterbury/alice29.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_gzip_best.gz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'gzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });

    test('with filename header readable by gzip CLI', () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec(filename: 'test.txt');
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_gzip_name.gz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'gzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });

    test('with comment header readable by gzip CLI', () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec(comment: 'Test comment');
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_gzip_comment.gz';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0,
            reason: 'gzip decompression failed: ${result.stderr}');
        final decompressed = result.stdout as List<int>;
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path]);
      }
    });
  });

  group('GZIP CLI Compatibility - Bidirectional round-trip', () {
    test('library compress -> CLI decompress -> CLI compress -> library decompress',
        () async {
      if (!await cliAvailableCached('gzip')) {
        markTestSkipped('gzip CLI tool not available');
        return;
      }

      final codec = GzipCodec();
      final original = readDataFixture('calgary/paper1');
      final libCompressed = codec.compress(original);

      final path = '/tmp/libcompress_gzip_bidir.gz';
      final out = '/tmp/libcompress_gzip_bidir.out';
      final cliPath = '/tmp/libcompress_gzip_cli.gz';

      try {
        // Library -> CLI decompress
        await File(path).writeAsBytes(libCompressed);
        final result = await Process.run(
          'gzip',
          ['-d', '-k', '-f', '-c', path],
          stdoutEncoding: null,
        );
        expect(result.exitCode, 0);
        final cliOut = result.stdout as List<int>;
        expect(cliOut, equals(original));

        // Write decompressed to file for re-compression
        await File(out).writeAsBytes(cliOut);

        // CLI compress -> Library decompress
        final result2 = await Process.run(
          'gzip',
          ['-k', '-f', '-c', out],
          stdoutEncoding: null,
        );
        expect(result2.exitCode, 0);
        await File(cliPath).writeAsBytes(result2.stdout as List<int>);

        final cliCompressed = await File(cliPath).readAsBytes();
        final libOut = codec.decompress(Uint8List.fromList(cliCompressed));
        expect(libOut, equals(original));
      } finally {
        await cleanup([path, out, cliPath]);
      }
    });
  });

  group('GZIP CLI Compatibility - All fixtures round-trip', () {
    for (final path in standardFixtures) {
      test('full round-trip for $path', () async {
        if (!await cliAvailableCached('gzip')) {
          markTestSkipped('gzip CLI tool not available');
          return;
        }

        final codec = GzipCodec();
        final original = readDataFixture(path);
        final libCompressed = codec.compress(original);

        final tmpPath =
            '/tmp/libcompress_gzip_rt_${path.replaceAll('/', '_')}.gz';

        try {
          await File(tmpPath).writeAsBytes(libCompressed);
          final result = await Process.run(
            'gzip',
            ['-d', '-k', '-c', tmpPath],
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

  group('GZIP CLI Compatibility - All compression levels', () {
    for (var level = 1; level <= 9; level++) {
      test('level $level output readable by gzip CLI', () async {
        if (!await cliAvailableCached('gzip')) {
          markTestSkipped('gzip CLI tool not available');
          return;
        }

        final codec = GzipCodec(level: level);
        final original = readDataFixture('html');
        final compressed = codec.compress(original);
        final path = '/tmp/libcompress_gzip_level$level.gz';

        try {
          await File(path).writeAsBytes(compressed);
          final result = await Process.run(
            'gzip',
            ['-d', '-k', '-c', path],
            stdoutEncoding: null,
          );
          expect(result.exitCode, 0,
              reason: 'gzip decompression failed at level $level');
          final decompressed = result.stdout as List<int>;
          expect(decompressed, equals(original));
        } finally {
          await cleanup([path]);
        }
      });
    }
  });
}
