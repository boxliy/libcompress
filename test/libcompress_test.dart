import 'dart:typed_data';
import 'package:libcompress/libcompress.dart';
import 'package:test/test.dart';

void main() {
  group('CodecFactory', () {
    test('creates LZ4 codec', () {
      final codec = CodecFactory.codec(CodecType.lz4);
      expect(codec, isA<Lz4Codec>());

      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });

    test('creates Snappy codec', () {
      final codec = CodecFactory.codec(CodecType.snappy);
      expect(codec, isA<SnappyCodec>());

      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });

    test('creates GZIP codec', () {
      final codec = CodecFactory.codec(CodecType.gzip);
      expect(codec, isA<GzipCodec>());

      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final compressed = codec.compress(data);
      final decompressed = codec.decompress(compressed);
      expect(decompressed, equals(data));
    });
  });
}
