import 'dart:typed_data';

import '../compression_stream_codec.dart';
import '../util/stream_compress_transformer.dart';
import '../util/stream_decompress_transformer.dart';
import 'lz4_common.dart';
import 'lz4_decoder.dart';
import 'lz4_encoder.dart';

/// Default maximum buffer size for stream decoders (64MB)
const int lz4DefaultMaxBufferSize = 64 * 1024 * 1024;

/// LZ4 streaming codec
///
/// Provides stream-based compression and decompression for LZ4.
/// Each chunk emitted during compression is a complete, independent
/// LZ4 frame that can be concatenated with others.
class Lz4StreamCodec extends CompressionStreamCodec {
  /// Compression level (1-9, where 9 enables high-compression mode)
  final int level;

  /// Block size for frame compression
  final int blockSize;

  /// Whether to include content checksum in output
  final bool checksum;

  /// Maximum decompressed size per frame (prevents OOM attacks)
  final int? maxSize;

  /// Maximum buffer size for compressed data before rejecting
  final int maxBufferSize;

  /// Chunk size for buffering input during compression
  final int chunkSize;

  /// Creates an LZ4 streaming codec
  Lz4StreamCodec({
    this.level = 1,
    this.blockSize = lz4DefaultBlockSize,
    this.checksum = true,
    this.maxSize = lz4DefaultMaxDecompressedSize,
    this.maxBufferSize = lz4DefaultMaxBufferSize,
    this.chunkSize = 1024 * 1024, // 1MB default
  });

  @override
  String get name => 'LZ4';

  @override
  Stream<Uint8List> compress(final Stream<Uint8List> input) {
    final encoder = Lz4Encoder(
      level: level,
      blockSize: blockSize,
      enableContentChecksum: checksum,
    );
    return StreamCompressTransformer(
      chunkSize: chunkSize,
      compress: encoder.compress,
    ).bind(input);
  }

  @override
  Stream<Uint8List> decompress(final Stream<Uint8List> input) {
    return _Lz4DecompressTransformer(
      maxSize: maxSize,
      maxBufferSize: maxBufferSize,
    ).bind(input);
  }
}

/// Transformer for LZ4 decompression
class _Lz4DecompressTransformer
    extends StreamDecompressTransformer<Lz4FormatException> {
  late final Lz4Decoder _decoder;

  _Lz4DecompressTransformer({
    super.maxSize,
    required super.maxBufferSize,
  }) {
    _decoder = Lz4Decoder(maxSize: maxSize);
  }

  @override
  int get minFrameSize => 7;

  @override
  bool isValidStart(final List<int> buffer, final int offset) =>
      buffer[offset] == 0x04 &&
      buffer[offset + 1] == 0x22 &&
      buffer[offset + 2] == 0x4D &&
      buffer[offset + 3] == 0x18;

  @override
  FrameParseResult? tryParseFrame(final List<int> buffer, final int offset) =>
      _tryParseFrame(buffer, offset);

  @override
  Uint8List decompress(final Uint8List frame) => _decoder.decompress(frame);

  @override
  Lz4FormatException createBufferError() => Lz4FormatException(
        'Stream buffer exceeded $maxBufferSize bytes - '
        'frame too large or malformed',
      );

  @override
  Lz4FormatException createMagicError(final List<int> buffer, final int offset) =>
      Lz4FormatException('Invalid LZ4 frame magic at offset $offset');

  @override
  Lz4FormatException createIncompleteError() =>
      Lz4FormatException('Incomplete LZ4 frame at end of stream');

  /// Try to parse a complete frame from buffer at offset, return null if incomplete
  FrameParseResult? _tryParseFrame(final List<int> buffer, final int offset) {
    if (buffer.length - offset < 7) return null;

    var pos = offset + 4; // Skip magic
    final flg = buffer[pos++];
    final bd = buffer[pos++];

    // Derive max block size from BD byte (bits 4-6)
    final blockSizeCode = (bd >> 4) & 0x07;
    int maxBlock;
    switch (blockSizeCode) {
      case 4:
        maxBlock = lz4BlockSize64K;
        break;
      case 5:
        maxBlock = lz4BlockSize256K;
        break;
      case 6:
        maxBlock = lz4BlockSize1M;
        break;
      case 7:
        maxBlock = lz4BlockSize4M;
        break;
      default:
        throw Lz4FormatException('Invalid block size code: $blockSizeCode');
    }

    // Content size (8 bytes if flag set)
    if ((flg & 0x08) != 0) {
      if (buffer.length < pos + 8) return null;
      pos += 8;
    }

    // Dict ID (4 bytes if flag set)
    if ((flg & 0x01) != 0) {
      if (buffer.length < pos + 4) return null;
      pos += 4;
    }

    // Header checksum
    if (buffer.length < pos + 1) return null;
    pos++;

    // Parse blocks until end mark
    final contentChecksum = (flg & 0x04) != 0;
    final blockChecksum = (flg & 0x10) != 0;

    while (true) {
      if (buffer.length < pos + 4) return null;

      final size = buffer[pos] |
          (buffer[pos + 1] << 8) |
          (buffer[pos + 2] << 16) |
          (buffer[pos + 3] << 24);
      pos += 4;

      if (size == 0) {
        // End mark found
        break;
      }

      final blockSize = size & 0x7FFFFFFF;

      // Validate block size against BD-derived maximum
      if (blockSize > maxBlock) {
        throw Lz4FormatException(
          'Block size $blockSize exceeds frame maximum $maxBlock bytes',
        );
      }

      if (buffer.length < pos + blockSize) return null;
      pos += blockSize;

      if (blockChecksum) {
        if (buffer.length < pos + 4) return null;
        pos += 4;
      }
    }

    // Content checksum
    if (contentChecksum) {
      if (buffer.length < pos + 4) return null;
      pos += 4;
    }

    final length = pos - offset;
    final frame = Uint8List.fromList(buffer.sublist(offset, pos));
    return FrameParseResult(frame, length);
  }
}
