import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:libcompress/libcompress.dart';
import 'test_utils.dart';

void main() {
  group('ZSTD CLI Compatibility - Decompress CLI-generated fixtures', () {
    for (final path in standardFixtures) {
      test('decompresses $path from zstd CLI', () {
        final codec = ZstdCodec();
        final original = readDataFixture(path);
        final compressed = readCodecFixture('zstd', '$path.zst');
        final decompressed = codec.decompress(compressed);
        expect(decompressed, equals(original));
      });
    }
  });

  group('ZSTD CLI Compatibility - Library output readable by CLI', () {
    test('RLE-compressed output readable by zstd CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      // Use repetitive data that compresses well with RLE
      final original = readDataFixture('artificial/aaa.txt');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_zstd_test.zst';
      final out = '/tmp/libcompress_zstd_test.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0,
            reason: 'zstd decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('zeros (RLE block) output readable by zstd CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      final original = readDataFixture('zeros.bin');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_zstd_zeros.zst';
      final out = '/tmp/libcompress_zstd_zeros.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0,
            reason: 'zstd decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('raw block output readable by zstd CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      // Random data uses raw blocks
      final original = readDataFixture('random.bin');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_zstd_raw.zst';
      final out = '/tmp/libcompress_zstd_raw.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0,
            reason: 'zstd decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('with checksum enabled readable by zstd CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec(enableChecksum: true);
      final original = readDataFixture('html');
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_zstd_checksum.zst';
      final out = '/tmp/libcompress_zstd_checksum.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0,
            reason: 'zstd decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });

    test('small block size output readable by zstd CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec(blockSize: 1000);
      final original = Uint8List.fromList(List.generate(2500, (i) => i % 256));
      final compressed = codec.compress(original);
      final path = '/tmp/libcompress_zstd_small_block.zst';
      final out = '/tmp/libcompress_zstd_small_block.out';

      try {
        await File(path).writeAsBytes(compressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0,
            reason: 'zstd decompression failed: ${result.stderr}');
        final decompressed = await File(out).readAsBytes();
        expect(decompressed, equals(original));
      } finally {
        await cleanup([path, out]);
      }
    });
  });

  group('ZSTD CLI Compatibility - Bidirectional round-trip', () {
    test('library compress -> CLI decompress -> CLI compress -> library decompress',
        () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      // Use data that can be compressed by our encoder
      final original = Uint8List.fromList(List.filled(10000, 65)); // All 'A's
      final libCompressed = codec.compress(original);

      final path = '/tmp/libcompress_zstd_bidir.zst';
      final out = '/tmp/libcompress_zstd_bidir.out';
      final cliPath = '/tmp/libcompress_zstd_cli.zst';

      try {
        // Library -> CLI decompress
        await File(path).writeAsBytes(libCompressed);
        final result = await Process.run('zstd', ['-d', '-f', '-o', out, path]);
        expect(result.exitCode, 0, reason: 'zstd CLI decompression failed');
        final cliOut = await File(out).readAsBytes();
        expect(cliOut, equals(original));

        // CLI compress -> Library decompress
        final result2 = await Process.run('zstd', ['-f', '-o', cliPath, out]);
        expect(result2.exitCode, 0);
        final cliCompressed = await File(cliPath).readAsBytes();
        final libOut = codec.decompress(Uint8List.fromList(cliCompressed));
        expect(libOut, equals(original));
      } finally {
        await cleanup([path, out, cliPath]);
      }
    });
  });

  group('ZSTD CLI Compatibility - All fixtures round-trip', () {
    for (final path in standardFixtures) {
      test('full round-trip for $path', () async {
        if (!await cliAvailableCached('zstd')) {
          markTestSkipped('zstd CLI tool not available');
          return;
        }

        final codec = ZstdCodec();
        final original = readDataFixture(path);
        final libCompressed = codec.compress(original);

        final tmpPath =
            '/tmp/libcompress_zstd_rt_${path.replaceAll('/', '_')}.zst';
        final tmpOut =
            '/tmp/libcompress_zstd_rt_${path.replaceAll('/', '_')}.out';

        try {
          await File(tmpPath).writeAsBytes(libCompressed);
          final result =
              await Process.run('zstd', ['-d', '-f', '-o', tmpOut, tmpPath]);
          expect(result.exitCode, 0,
              reason: 'CLI decompression failed for $path');
          final cliOut = await File(tmpOut).readAsBytes();
          expect(cliOut, equals(original),
              reason: 'Round-trip mismatch for $path');
        } finally {
          await cleanup([tmpPath, tmpOut]);
        }
      });
    }
  });

  group('ZSTD CLI Compatibility - Huffman-compressed blocks', () {
    // These fixtures are compressed by CLI zstd with Huffman encoding
    test('decompresses CLI-compressed html (Huffman + sequences)', () {
      final codec = ZstdCodec();
      final compressed = readCodecFixture('zstd', 'html.zst');
      final expected = readDataFixture('html');
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(expected));
      // Verify meaningful compression was achieved
      expect(compressed.length, lessThan(expected.length ~/ 4));
    });

    test('decompresses CLI-compressed alice29.txt (Huffman + sequences)', () {
      final codec = ZstdCodec();
      final compressed = readCodecFixture('zstd', 'canterbury/alice29.txt.zst');
      final expected = readDataFixture('canterbury/alice29.txt');
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(expected));
    });

    test('decompresses CLI-compressed paper1 (Huffman + sequences)', () {
      final codec = ZstdCodec();
      final compressed = readCodecFixture('zstd', 'calgary/paper1.zst');
      final expected = readDataFixture('calgary/paper1');
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(expected));
    });

    test('library decompresses CLI Huffman at various compression levels',
        () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      final original = readDataFixture('html');
      final tmpIn = '/tmp/libcompress_zstd_huffman_in.txt';
      final tmpOut = '/tmp/libcompress_zstd_huffman.zst';

      try {
        await File(tmpIn).writeAsBytes(original);

        // Test various compression levels (all use Huffman for text)
        for (final level in [1, 3, 9, 19]) {
          final result = await Process.run(
            'zstd',
            ['-$level', '-f', '-o', tmpOut, tmpIn],
          );
          expect(result.exitCode, 0,
              reason: 'CLI compression failed at level $level');

          final compressed = await File(tmpOut).readAsBytes();
          final decompressed = codec.decompress(Uint8List.fromList(compressed));
          expect(decompressed, equals(original),
              reason: 'Decompression failed at level $level');
        }
      } finally {
        await cleanup([tmpIn, tmpOut]);
      }
    });

    test('handles 4-stream Huffman from CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      // Large data triggers 4-stream Huffman encoding
      final original = readDataFixture('canterbury/alice29.txt');
      final tmpIn = '/tmp/libcompress_zstd_4stream_in.txt';
      final tmpOut = '/tmp/libcompress_zstd_4stream.zst';

      try {
        await File(tmpIn).writeAsBytes(original);
        final result = await Process.run('zstd', ['-f', '-o', tmpOut, tmpIn]);
        expect(result.exitCode, 0);

        final compressed = await File(tmpOut).readAsBytes();
        final decompressed = codec.decompress(Uint8List.fromList(compressed));
        expect(decompressed, equals(original));
      } finally {
        await cleanup([tmpIn, tmpOut]);
      }
    });

    test('handles single-stream Huffman from CLI', () async {
      if (!await cliAvailableCached('zstd')) {
        markTestSkipped('zstd CLI tool not available');
        return;
      }

      final codec = ZstdCodec();
      // Small data uses single-stream Huffman
      final original = Uint8List.fromList(
        'Hello, World! This is a small test string for Huffman encoding.'
            .codeUnits,
      );
      final tmpIn = '/tmp/libcompress_zstd_1stream_in.txt';
      final tmpOut = '/tmp/libcompress_zstd_1stream.zst';

      try {
        await File(tmpIn).writeAsBytes(original);
        final result = await Process.run('zstd', ['-f', '-o', tmpOut, tmpIn]);
        expect(result.exitCode, 0);

        final compressed = await File(tmpOut).readAsBytes();
        final decompressed = codec.decompress(Uint8List.fromList(compressed));
        expect(decompressed, equals(original));
      } finally {
        await cleanup([tmpIn, tmpOut]);
      }
    });
  });

  group('ZSTD edge cases', () {
    test('compresses and decompresses empty data', () {
      final codec = ZstdCodec();
      final data = Uint8List(0);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });

    test('compresses and decompresses single byte', () {
      final codec = ZstdCodec();
      final data = Uint8List.fromList([42]);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });

    test('compresses and decompresses highly repetitive data', () {
      final codec = ZstdCodec();
      final data = Uint8List.fromList(List.filled(10000, 65));
      final compressed = codec.compress(data);
      expect(compressed.length, lessThan(100)); // RLE compression
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });
  });
}
