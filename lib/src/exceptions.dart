/// Base exception class for compression format errors
///
/// This is the common base class for all compression-related format exceptions.
/// Each codec has a specific subclass for codec-specific error handling:
/// - [Lz4FormatException] for LZ4 format errors
/// - [GzipFormatException] for GZIP format errors
/// - [ZstdFormatException] for Zstandard format errors
/// - [SnappyFormatException] for Snappy format errors
///
/// All subclasses extend [FormatException] for consistency with Dart's
/// standard library conventions.
/// TODO: Maybe move these to the implementations?
///
/// Example:
/// ```dart
/// try {
///   final data = codec.decompress(compressed);
/// } on CompressionFormatException catch (e) {
///   print('Compression error: ${e.message}');
/// }
/// ```
abstract class CompressionFormatException extends FormatException {
  /// Creates a compression format exception with the given [message].
  const CompressionFormatException(super.message);
}

/// Exception thrown when invalid LZ4 data is encountered
class Lz4FormatException extends CompressionFormatException {
  /// Creates an LZ4 format exception with the given [message].
  const Lz4FormatException(super.message);

  @override
  String toString() => 'Lz4FormatException: $message';
}

/// Exception thrown when invalid GZIP data is encountered
class GzipFormatException extends CompressionFormatException {
  /// Creates a GZIP format exception with the given [message].
  const GzipFormatException(super.message);

  @override
  String toString() => 'GzipFormatException: $message';
}

/// Exception thrown during DEFLATE compression/decompression
class DeflateFormatException extends CompressionFormatException {
  /// Creates a DEFLATE format exception with the given [message].
  const DeflateFormatException(super.message);

  @override
  String toString() => 'DeflateFormatException: $message';
}

/// Exception thrown when invalid Zstandard data is encountered
class ZstdFormatException extends CompressionFormatException {
  /// Creates a Zstandard format exception with the given [message].
  const ZstdFormatException(super.message);

  @override
  String toString() => 'ZstdFormatException: $message';
}

/// Exception thrown when invalid Snappy data is encountered
class SnappyFormatException extends CompressionFormatException {
  /// Creates a Snappy format exception with the given [message].
  const SnappyFormatException(super.message);

  @override
  String toString() => 'SnappyFormatException: $message';
}
