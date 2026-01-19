/// Base class for compression codec configuration options
///
/// Provides common configuration parameters that apply to most compression
/// algorithms. Specific codecs extend this class to add algorithm-specific
/// options.
abstract class CompressionOptions {
  /// The compression level (codec-specific range)
  ///
  /// Typical ranges:
  /// - GZIP/LZ4: 1-9 (1=fastest, 9=best)
  /// - Zstd: 1-22 (1=fastest, 22=best)
  /// - Snappy: ignored (no levels)
  ///
  /// Not all codecs support all levels. Some may map ranges to specific modes.
  final int level;

  /// Whether to include content checksums for integrity verification
  ///
  /// When enabled, adds checksums to compressed output that can be verified
  /// during decompression. Slightly increases compressed size and processing time.
  ///
  /// Note: Not all codecs respect this setting. GZIP always includes CRC32
  /// checksums. Use codec-specific constructors for fine control.
  final bool checksum;

  /// Creates compression options with specified parameters
  ///
  /// Level validation is codec-specific - see subclass constructors.
  /// Throws [ArgumentError] if level is less than 1.
  CompressionOptions({
    this.level = 5,
    this.checksum = true,
  }) {
    if (level < 1) {
      throw ArgumentError.value(level, 'level', 'Must be at least 1');
    }
  }
}

/// Compression level presets for common use cases
enum CompressionLevel {
  /// Fastest compression, prioritizes speed over ratio
  fast(1),

  /// Balanced compression suitable for most cases
  normal(5),

  /// Best compression, prioritizes ratio over speed
  best(9);

  /// The numeric compression level
  final int value;

  const CompressionLevel(this.value);
}
