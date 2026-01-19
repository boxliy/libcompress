import 'compression_codec.dart';
import 'compression_stream_codec.dart';
import 'noop/noop_codec.dart';
import 'noop/noop_stream_codec.dart';
import 'snappy/snappy_codec.dart';
import 'snappy/snappy_stream_codec.dart';
import 'gzip/gzip_codec.dart';
import 'gzip/gzip_stream_codec.dart';
import 'lz4/lz4_codec.dart';
import 'lz4/lz4_stream_codec.dart';
import 'zstd/zstd_codec.dart';
import 'zstd/zstd_stream_codec.dart';

/// Supported compression codec types
enum CodecType {
  noop,
  snappy,
  gzip,
  lz4,
  zstd;

  /// Parse a string to a CodecType
  static CodecType parse(final String value) {
    return CodecType.values.firstWhere(
      (final type) => type.name == value,
      orElse: () => throw ArgumentError('Unknown codec type: $value'),
    );
  }
}

/// Factory for creating compression codecs
///
/// Provides methods to create both block-based ([CompressionCodec]) and
/// stream-based ([CompressionStreamCodec]) codec instances.
class CodecFactory {
  /// All supported codec types
  static const types = CodecType.values;

  /// Get a block-based codec for the given type
  ///
  /// Example:
  /// ```dart
  /// final codec = CodecFactory.codec(CodecType.lz4);
  /// final compressed = codec.compress(data);
  /// ```
  static CompressionCodec codec(final CodecType type) {
    return switch (type) {
      CodecType.noop => NoopCodec(),
      CodecType.snappy => SnappyCodec(),
      CodecType.gzip => GzipCodec(),
      CodecType.lz4 => Lz4Codec(),
      CodecType.zstd => ZstdCodec(),
    };
  }

  /// Get a stream-based codec for the given type
  ///
  /// Example:
  /// ```dart
  /// final codec = CodecFactory.streaming(CodecType.lz4);
  /// final compressed = await codec.compress(inputStream).toList();
  /// ```
  static CompressionStreamCodec streaming(final CodecType type) {
    return switch (type) {
      CodecType.noop => NoopStreamCodec(),
      CodecType.snappy => SnappyStreamCodec(),
      CodecType.gzip => GzipStreamCodec(),
      CodecType.lz4 => Lz4StreamCodec(),
      CodecType.zstd => ZstdStreamCodec(),
    };
  }

  /// Check if a codec type supports a given mode
  ///
  /// Example:
  /// ```dart
  /// if (CodecFactory.supports(CodecType.lz4, CodecMode.stream)) {
  ///   final streamCodec = CodecFactory.streaming(CodecType.lz4);
  /// }
  /// ```
  static bool supports(final CodecType type, final CodecMode mode) {
    return codec(type).supports(mode);
  }
}
