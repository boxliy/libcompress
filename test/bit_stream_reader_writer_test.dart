import 'dart:typed_data';
import 'package:libcompress/src/util/bit_stream.dart';
import 'package:test/test.dart';

void main() {
  group('BitStream', () {
    test('round-trip test with various bit lengths', () {
      final writer = BitStreamWriter();

      // A list of (value, bitCount) pairs to write.
      final testData = [
        [5, 3], // 101
        [10, 4], // 1010
        [2, 2], // 10
        [31, 5], // 11111
        [0, 1], // 0
        [1, 1], // 1
        [12345, 14],
        [67890, 17],
      ];

      // Write all test data to the stream.
      for (final item in testData) {
        writer.writeBits(item[0], item[1]);
      }

      final Uint8List bytes = writer.toBytes();
      final reader = BitStreamReader(bytes);

      // Read the data back and verify it.
      for (final item in testData) {
        final value = item[0];
        final bitCount = item[1];
        final readValue = reader.readBits(bitCount);
        expect(
          readValue,
          equals(value),
          reason: 'Failed on $bitCount-bit value $value',
        );
      }
    });

    test('write and read a single byte', () {
      final writer = BitStreamWriter();
      writer.writeBits(0xAB, 8);

      final bytes = writer.toBytes();
      expect(bytes, equals(Uint8List.fromList([0xAB])));

      final reader = BitStreamReader(bytes);
      expect(reader.readBits(8), equals(0xAB));
    });

    test('write and read across byte boundaries', () {
      final writer = BitStreamWriter();
      // Write 4 bits, then 8 bits. The 8-bit value will cross a byte boundary.
      writer.writeBits(0xF, 4); // 1111
      writer.writeBits(0xA5, 8); // 10100101

      final bytes = writer.toBytes();
      // Expected bytes:
      // First byte: lower 4 bits of 0xA5 + 4 bits of 0xF -> 01011111 -> 0x5F
      // Second byte: upper 4 bits of 0xA5 -> 1010 -> 0x0A
      expect(bytes, equals(Uint8List.fromList([0x5F, 0x0A])));

      final reader = BitStreamReader(bytes);
      expect(reader.readBits(4), equals(0xF));
      expect(reader.readBits(8), equals(0xA5));
    });
  });
}
