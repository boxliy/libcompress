import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:libcompress/src/snappy/snappy_stream_encoder.dart';
import 'package:libcompress/src/snappy/snappy_stream_decoder.dart';
import 'package:libcompress/libcompress.dart';

void main() {
  group('Snappy streaming (framing format)', () {
    test('encodes stream identifier correctly', () {
      final encoder = SnappyStreamEncoder();
      final compressed = encoder.compress(Uint8List(0));

      // Should start with stream identifier
      expect(compressed.length, greaterThanOrEqualTo(10));
      expect(compressed[0], 0xff); // Stream identifier type
      expect(compressed[1], 0x06); // Length = 6
      expect(compressed[2], 0x00);
      expect(compressed[3], 0x00);
      expect(compressed[4], 0x73); // 's'
      expect(compressed[5], 0x4e); // 'N'
      expect(compressed[6], 0x61); // 'a'
      expect(compressed[7], 0x50); // 'P'
      expect(compressed[8], 0x70); // 'p'
      expect(compressed[9], 0x59); // 'Y'
    });

    test('round-trips empty data', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      final original = Uint8List(0);
      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips single byte', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      final original = Uint8List.fromList([42]);
      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips small data', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      final original = Uint8List.fromList('Hello, Snappy!'.codeUnits);
      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips data exactly at chunk boundary', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      // Exactly 65536 bytes
      final original = Uint8List(65536);
      for (var i = 0; i < original.length; i++) {
        original[i] = i & 0xff;
      }

      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips data larger than one chunk', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      // 100KB of data (will be split into 2 chunks)
      final original = Uint8List(100 * 1024);
      for (var i = 0; i < original.length; i++) {
        original[i] = i & 0xff;
      }

      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips with custom chunk size', () {
      final encoder = SnappyStreamEncoder(chunkSize: 1024);
      final decoder = SnappyStreamDecoder();

      final original = Uint8List(5000);
      for (var i = 0; i < original.length; i++) {
        original[i] = i & 0xff;
      }

      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('round-trips highly compressible data', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder();

      // 100KB of repeated pattern
      final original = Uint8List(100 * 1024);
      for (var i = 0; i < original.length; i++) {
        original[i] = (i % 256) & 0xff;
      }

      final compressed = encoder.compress(original);
      final decompressed = decoder.decompress(compressed);

      expect(decompressed, equals(original));
      // Should compress well
      expect(compressed.length, lessThan(original.length));
    });

    test('rejects invalid stream identifier', () {
      final decoder = SnappyStreamDecoder();

      final invalid = Uint8List.fromList([
        0xff, 0x06, 0x00, 0x00, // Header
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Wrong identifier
      ]);

      expect(() => decoder.decompress(invalid), throwsFormatException);
    });

    test('rejects data without stream identifier', () {
      final decoder = SnappyStreamDecoder();

      // Start with a compressed chunk (no stream identifier)
      final invalid = Uint8List.fromList([
        0x00, 0x04, 0x00, 0x00, // Compressed chunk header
        0x00, 0x00, 0x00, 0x00, // Checksum
      ]);

      expect(() => decoder.decompress(invalid), throwsFormatException);
    });

    test('rejects chunk with invalid checksum', () {
      final decoder = SnappyStreamDecoder();

      // Valid stream identifier + chunk with wrong checksum
      final invalid = BytesBuilder();
      invalid.addByte(0xff);
      invalid.addByte(0x06);
      invalid.addByte(0x00);
      invalid.addByte(0x00);
      invalid.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]); // "sNaPpY"

      // Uncompressed chunk with wrong checksum
      invalid.addByte(0x01); // Uncompressed
      invalid.addByte(0x05); // Length = 5
      invalid.addByte(0x00);
      invalid.addByte(0x00);
      invalid.addByte(0xFF); // Wrong checksum
      invalid.addByte(0xFF);
      invalid.addByte(0xFF);
      invalid.addByte(0xFF);
      invalid.addByte(0x42); // Single byte of data

      expect(
        () => decoder.decompress(Uint8List.fromList(invalid.toBytes())),
        throwsFormatException,
      );
    });

    test('rejects unskippable reserved chunk', () {
      final decoder = SnappyStreamDecoder();

      final invalid = BytesBuilder();
      invalid.addByte(0xff);
      invalid.addByte(0x06);
      invalid.addByte(0x00);
      invalid.addByte(0x00);
      invalid.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]); // Stream ID

      // Reserved unskippable chunk (0x02-0x7f)
      invalid.addByte(0x02); // Reserved unskippable
      invalid.addByte(0x00);
      invalid.addByte(0x00);
      invalid.addByte(0x00);

      expect(
        () => decoder.decompress(Uint8List.fromList(invalid.toBytes())),
        throwsFormatException,
      );
    });

    test('skips reserved skippable chunks', () {
      final decoder = SnappyStreamDecoder();

      final data = BytesBuilder();
      data.addByte(0xff);
      data.addByte(0x06);
      data.addByte(0x00);
      data.addByte(0x00);
      data.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]); // Stream ID

      // Add a skippable chunk (0x80-0xfd)
      data.addByte(0x80); // Skippable
      data.addByte(0x04); // Length = 4
      data.addByte(0x00);
      data.addByte(0x00);
      data.add([0xDE, 0xAD, 0xBE, 0xEF]); // Random data

      // Should decompress successfully (output is empty, but no error)
      final result = decoder.decompress(Uint8List.fromList(data.toBytes()));
      expect(result.length, 0);
    });

    test('handles padding chunks', () {
      final decoder = SnappyStreamDecoder();

      final data = BytesBuilder();
      data.addByte(0xff);
      data.addByte(0x06);
      data.addByte(0x00);
      data.addByte(0x00);
      data.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]); // Stream ID

      // Add padding chunk
      data.addByte(0xfe); // Padding
      data.addByte(0x08); // Length = 8
      data.addByte(0x00);
      data.addByte(0x00);
      data.add(List.filled(8, 0)); // 8 zero bytes

      // Should decompress successfully (padding ignored)
      final result = decoder.decompress(Uint8List.fromList(data.toBytes()));
      expect(result.length, 0);
    });

    test('enforces maxUncompressedSize limit', () {
      final encoder = SnappyStreamEncoder();
      final decoder = SnappyStreamDecoder(maxUncompressedSize: 100);

      // Create data that will exceed limit when decompressed
      final original = Uint8List(200);
      final compressed = encoder.compress(original);

      expect(() => decoder.decompress(compressed), throwsFormatException);
    });

    test('works via SnappyCodec with framing=true', () {
      final codec = SnappyCodec(framing: true);

      final original = Uint8List.fromList('Test data for codec'.codeUnits);
      final compressed = codec.compress(original);
      final decompressed = codec.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('codec allows custom chunk size', () {
      final codec = SnappyCodec(framing: true, chunkSize: 1024);

      final original = Uint8List(5000);
      for (var i = 0; i < original.length; i++) {
        original[i] = i & 0xff;
      }

      final compressed = codec.compress(original);
      final decompressed = codec.decompress(compressed);

      expect(decompressed, equals(original));
    });

    test('rejects invalid chunk size', () {
      expect(
        () => SnappyStreamEncoder(chunkSize: 0),
        throwsArgumentError,
      );

      expect(
        () => SnappyStreamEncoder(chunkSize: 65537),
        throwsArgumentError,
      );
    });

    test('handles multiple stream identifiers', () {
      final decoder = SnappyStreamDecoder();

      final data = BytesBuilder();
      // First stream identifier
      data.addByte(0xff);
      data.addByte(0x06);
      data.addByte(0x00);
      data.addByte(0x00);
      data.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]);

      // Second stream identifier (should be ignored per spec)
      data.addByte(0xff);
      data.addByte(0x06);
      data.addByte(0x00);
      data.addByte(0x00);
      data.add([0x73, 0x4e, 0x61, 0x50, 0x70, 0x59]);

      // Should not throw
      final result = decoder.decompress(Uint8List.fromList(data.toBytes()));
      expect(result.length, 0);
    });
  });
}
