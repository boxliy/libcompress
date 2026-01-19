import 'dart:typed_data';

import '../compression_stream_codec.dart';
import '../util/stream_compress_transformer.dart';
import '../util/stream_decompress_transformer.dart';
import 'zstd_common.dart';
import 'zstd_compressor.dart';
import 'zstd_decoder.dart';

/// Default maximum buffer size for stream decoders (64MB)
const int zstdDefaultMaxBufferSize = 64 * 1024 * 1024;

/// Zstd streaming codec
///
/// Provides stream-based compression and decompression for Zstd.
/// Each chunk emitted during compression is a complete, independent
/// Zstd frame that can be concatenated with others.
class ZstdStreamCodec extends CompressionStreamCodec {
  /// Compression level (1-22)
  final int level;

  /// Block size for frame compression
  final int blockSize;

  /// Whether to include XXH64 content checksum
  final bool checksum;

  /// Maximum decompressed size per frame (prevents OOM attacks)
  final int? maxSize;

  /// Maximum buffer size for compressed data before rejecting
  final int maxBufferSize;

  /// Chunk size for buffering input during compression
  final int chunkSize;

  /// Whether to validate compressed blocks by decompressing them
  final bool validate;

  /// Creates a Zstd streaming codec
  ZstdStreamCodec({
    this.level = 3,
    this.blockSize = 128 * 1024,
    this.checksum = false,
    this.maxSize = zstdDefaultMaxDecompressedSize,
    this.maxBufferSize = zstdDefaultMaxBufferSize,
    this.chunkSize = 1024 * 1024, // 1MB default
    this.validate = false,
  });

  @override
  String get name => 'ZSTD';

  @override
  Stream<Uint8List> compress(final Stream<Uint8List> input) {
    final compressor = ZstdCompressor(
      level: level,
      blockSize: blockSize,
      enableChecksum: checksum,
      validate: validate,
    );
    return StreamCompressTransformer(
      chunkSize: chunkSize,
      compress: compressor.compress,
    ).bind(input);
  }

  @override
  Stream<Uint8List> decompress(final Stream<Uint8List> input) {
    return _ZstdDecompressTransformer(
      maxSize: maxSize,
      maxBufferSize: maxBufferSize,
    ).bind(input);
  }
}

/// Transformer for Zstd decompression
class _ZstdDecompressTransformer
    extends StreamDecompressTransformer<ZstdFormatException> {
  late final ZstdDecoder _decoder;

  _ZstdDecompressTransformer({
    super.maxSize,
    required super.maxBufferSize,
  }) {
    _decoder = ZstdDecoder(maxSize: maxSize);
  }

  @override
  int get minFrameSize => 8;

  @override
  bool isValidStart(final List<int> buffer, final int offset) {
    final magic = buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24);
    final isSkippable =
        (magic & zstdSkippableFrameMagicMask) == zstdSkippableFrameMagicBase;
    return magic == zstdMagicNumber || isSkippable;
  }

  @override
  FrameParseResult? tryParseFrame(final List<int> buffer, final int offset) =>
      _tryParseFrame(buffer, offset);

  @override
  Uint8List decompress(final Uint8List frame) => _decoder.decompress(frame);

  @override
  ZstdFormatException createBufferError() => ZstdFormatException(
        'Stream buffer exceeded $maxBufferSize bytes - '
        'frame too large or malformed',
      );

  @override
  ZstdFormatException createMagicError(final List<int> buffer, final int offset) {
    final magic = buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24);
    return ZstdFormatException(
      'Invalid Zstd frame magic: 0x${magic.toRadixString(16)} at offset $offset',
    );
  }

  @override
  ZstdFormatException createIncompleteError() =>
      ZstdFormatException('Incomplete Zstd frame at end of stream');

  /// Try to parse a complete frame from buffer at offset, return null if incomplete
  FrameParseResult? _tryParseFrame(final List<int> buffer, final int offset) {
    if (buffer.length - offset < 8) return null;

    final magic = buffer[offset] |
        (buffer[offset + 1] << 8) |
        (buffer[offset + 2] << 16) |
        (buffer[offset + 3] << 24);

    // Handle skippable frames
    if ((magic & zstdSkippableFrameMagicMask) == zstdSkippableFrameMagicBase) {
      final size = buffer[offset + 4] |
          (buffer[offset + 5] << 8) |
          (buffer[offset + 6] << 16) |
          (buffer[offset + 7] << 24);
      final total = 8 + size;
      if (buffer.length - offset < total) return null;
      final frame = Uint8List.fromList(buffer.sublist(offset, offset + total));
      return FrameParseResult(frame, total);
    }

    // Parse Zstd frame
    var pos = offset + 4; // Skip magic

    // Frame header descriptor
    if (buffer.length < pos + 1) return null;
    final descriptor = buffer[pos++];

    final singleSegment = (descriptor & 0x20) != 0;
    final contentChecksumFlag = (descriptor & 0x04) != 0;
    final dictIdFlag = descriptor & 0x03;
    final fcsFieldSize = (descriptor >> 6) & 0x03;

    // Window descriptor (only if not single segment)
    if (!singleSegment) {
      if (buffer.length < pos + 1) return null;
      pos++;
    }

    // Dictionary ID
    final dictIdSize = dictIdFlag == 0 ? 0 : (1 << (dictIdFlag - 1));
    if (buffer.length < pos + dictIdSize) return null;
    pos += dictIdSize;

    // Frame Content Size
    var fcsSize = 0;
    if (singleSegment && fcsFieldSize == 0) {
      fcsSize = 1;
    } else if (fcsFieldSize > 0) {
      fcsSize = 1 << fcsFieldSize;
    }
    if (buffer.length < pos + fcsSize) return null;
    pos += fcsSize;

    // Parse blocks
    while (true) {
      if (buffer.length < pos + 3) return null;

      final blockHeader = buffer[pos] |
          (buffer[pos + 1] << 8) |
          (buffer[pos + 2] << 16);
      pos += 3;

      final lastBlock = (blockHeader & 0x01) != 0;
      final blockType = (blockHeader >> 1) & 0x03;
      final blockSize = blockHeader >> 3;

      // Validate block size against spec limit (128KB max)
      if (blockSize > zstdMaxBlockSize) {
        throw ZstdFormatException(
          'Block size $blockSize exceeds maximum $zstdMaxBlockSize bytes',
        );
      }

      if (blockType == 3) {
        throw ZstdFormatException('Reserved block type encountered');
      }

      final payloadSize = blockType == 1 ? 1 : blockSize;
      if (buffer.length < pos + payloadSize) return null;
      pos += payloadSize;

      if (lastBlock) break;
    }

    // Content checksum (4 bytes if flag set)
    if (contentChecksumFlag) {
      if (buffer.length < pos + 4) return null;
      pos += 4;
    }

    final length = pos - offset;
    final frame = Uint8List.fromList(buffer.sublist(offset, pos));
    return FrameParseResult(frame, length);
  }
}
