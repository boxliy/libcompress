import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:libcompress/libcompress.dart';
import 'test_utils.dart';

void main() {
  group('LZ4 CLI Compatibility - Decompress CLI-generated fixtures', () {
    for (final path in standardFixtures) {
      test('decompresses $path from lz4 CLI', () {
        final codec = Lz4Codec();
        final original = readDataFixture(path);
        final compressed = readCodecFixture('lz4', '$path.lz4');
        final decompressed = codec.decompress(compressed);
        expect(decompressed, equals(original));
      });
    }
  });

  group('LZ4 CLI Compatibility - Library output readable by CLI', () {
    test('fast compression output readable by lz4 CLI', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec(level: 1);
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_lz4_fast.lz4';
      final out = '/tmp/libcompress_lz4_fast.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0, reason: 'lz4 decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('HC compression output readable by lz4 CLI', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec(level: 9);
      final original = readDataFixture('canterbury/alice29.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_lz4_hc.lz4';
      final out = '/tmp/libcompress_lz4_hc.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0, reason: 'lz4 decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('64K block size output readable by lz4 CLI', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec(blockSize: lz4BlockSize64K);
      final original = readDataFixture('canterbury/alice29.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_lz4_64k.lz4';
      final out = '/tmp/libcompress_lz4_64k.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0, reason: 'lz4 decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('no checksum output readable by lz4 CLI', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec(enableContentChecksum: false);
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_lz4_nocheck.lz4';
      final out = '/tmp/libcompress_lz4_nocheck.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0, reason: 'lz4 decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });
  });

  group('LZ4 CLI Compatibility - Bidirectional round-trip', () {
    test('library compress -> CLI decompress -> CLI compress -> library decompress', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec();
      final original = readDataFixture('calgary/paper1');
      final libCompressed = codec.compress(original);

      final path = '/tmp/libcompress_lz4_bidir.lz4';
      final out = '/tmp/libcompress_lz4_bidir.out';
      final cliPath = '/tmp/libcompress_lz4_cli.lz4';

      try {
        // Library -> CLI decompress
        await File(path).writeAsBytes(libCompressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0);
        final cliOut = await File(out).readAsBytes();
        expect(cliOut, equals(original));

        // CLI compress -> Library decompress
        final result2 = await Process.run('lz4', ['-f', out, cliPath]);
        expect(result2.exitCode, 0);
        final cliCompressed = await File(cliPath).readAsBytes();
        final libOut = codec.decompress(Uint8List.fromList(cliCompressed));
        expect(libOut, equals(original));
      } finally {
        await cleanup([path, out, cliPath]);
      }
    });

    test('HC bidirectional round-trip with CLI', () async {
      if (!await cliAvailableCached('lz4')) {
        markTestSkipped('lz4 CLI tool not available');
        return;
      }

      final codec = Lz4Codec(level: 9);
      final original = readDataFixture('canterbury/alice29.txt');
      final libCompressed = codec.compress(original);

      final path = '/tmp/libcompress_lz4_hc_bidir.lz4';
      final out = '/tmp/libcompress_lz4_hc_bidir.out';
      final cliPath = '/tmp/libcompress_lz4_hc_cli.lz4';

      try {
        // Library HC -> CLI decompress
        await File(path).writeAsBytes(libCompressed);
        final result = await Process.run('lz4', ['-d', '-f', path, out]);
        expect(result.exitCode, 0);
        final cliOut = await File(out).readAsBytes();
        expect(cliOut, equals(original));

        // CLI HC compress -> Library decompress
        final result2 = await Process.run('lz4', ['-9', '-f', out, cliPath]);
        expect(result2.exitCode, 0);
        final cliCompressed = await File(cliPath).readAsBytes();
        final libOut = codec.decompress(Uint8List.fromList(cliCompressed));
        expect(libOut, equals(original));
      } finally {
        await cleanup([path, out, cliPath]);
      }
    });
  });

  group('LZ4 CLI Compatibility - All fixtures round-trip', () {
    for (final path in standardFixtures) {
      test('full round-trip for $path', () async {
        if (!await cliAvailableCached('lz4')) {
          markTestSkipped('lz4 CLI tool not available');
          return;
        }

        final codec = Lz4Codec();
        final original = readDataFixture(path);
        final libCompressed = codec.compress(original);

        final tmpPath = '/tmp/libcompress_lz4_rt_${path.replaceAll('/', '_')}.lz4';
        final tmpOut = '/tmp/libcompress_lz4_rt_${path.replaceAll('/', '_')}.out';

        try {
          await File(tmpPath).writeAsBytes(libCompressed);
          final result = await Process.run('lz4', ['-d', '-f', tmpPath, tmpOut]);
          expect(result.exitCode, 0, reason: 'CLI decompression failed for $path');
          final cliOut = await File(tmpOut).readAsBytes();
          expect(cliOut, equals(original), reason: 'Round-trip mismatch for $path');
        } finally {
          await cleanup([tmpPath, tmpOut]);
        }
      });
    }
  });
}
