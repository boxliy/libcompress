import 'dart:typed_data';

import '../compression_stream_codec.dart';
import '../util/stream_compress_transformer.dart';
import '../util/stream_decompress_transformer.dart';
import 'snappy_decoder.dart';
import 'snappy_stream_decoder.dart';
import 'snappy_stream_encoder.dart';

/// Default maximum buffer size for stream decoders (64MB)
const int snappyDefaultMaxBufferSize = 64 * 1024 * 1024;

/// Snappy streaming codec
///
/// Provides stream-based compression and decompression using the
/// Snappy framing format. The framing format allows for streaming
/// decompression and chunk-based processing.
class SnappyStreamCodec extends CompressionStreamCodec {
  /// Maximum uncompressed size per chunk
  final int maxSize;

  /// Maximum buffer size for compressed data before rejecting
  final int maxBufferSize;

  /// Chunk size for compression (max 65536 per spec)
  final int chunkSize;

  /// Creates a Snappy streaming codec
  SnappyStreamCodec({
    this.maxSize = SnappyDecoder.defaultMaxSize,
    this.maxBufferSize = snappyDefaultMaxBufferSize,
    this.chunkSize = SnappyStreamEncoder.maxChunkSize,
  });

  @override
  String get name => 'SNAPPY';

  @override
  Stream<Uint8List> compress(final Stream<Uint8List> input) {
    final encoder = SnappyStreamEncoder(chunkSize: chunkSize);
    return StreamCompressTransformer(
      chunkSize: chunkSize,
      header: () => encoder.streamIdentifier,
      compress: encoder.compressChunkOnly,
    ).bind(input);
  }

  @override
  Stream<Uint8List> decompress(final Stream<Uint8List> input) {
    return _SnappyDecompressTransformer(
      maxSize: maxSize,
      maxBufferSize: maxBufferSize,
    ).bind(input);
  }
}

/// Transformer for Snappy decompression
///
/// This transformer implements true incremental streaming by processing
/// each Snappy chunk individually rather than buffering entire frames.
class _SnappyDecompressTransformer
    extends StreamDecompressTransformer<SnappyFormatException> {
  final int _maxUncompressedSize;
  late final SnappyStreamDecoder _decoder;

  /// Whether we've seen the stream identifier
  bool _seenIdentifier = false;

  _SnappyDecompressTransformer({
    required int maxSize,
    required super.maxBufferSize,
  })  : _maxUncompressedSize = maxSize,
        super(maxSize: maxSize) {
    _decoder = SnappyStreamDecoder(maxUncompressedSize: _maxUncompressedSize);
  }

  // Minimum frame size is 4 bytes (chunk header)
  // First chunk (stream identifier) is 10 bytes, but we handle that in isValidStart
  @override
  int get minFrameSize => 4;

  @override
  bool isValidStart(final List<int> buffer, final int offset) {
    final type = buffer[offset];

    if (!_seenIdentifier) {
      // First chunk must be stream identifier
      return type == SnappyStreamEncoder.chunkTypeStreamIdentifier;
    }

    // After identifier, accept valid chunk types:
    // 0x00 = compressed, 0x01 = uncompressed, 0xfe = padding
    // 0x02-0x7f = reserved unskippable (will error in decompress)
    // 0x80-0xfd = reserved skippable (allowed)
    // 0xff = stream identifier (allowed, starts new stream)
    return true; // Let decompress handle validation
  }

  @override
  FrameParseResult? tryParseFrame(final List<int> buffer, final int offset) =>
      _tryParseChunk(buffer, offset);

  @override
  Uint8List decompress(final Uint8List frame) {
    // Use incremental chunk decompression
    final result = _decoder.decompressChunk(frame);
    // Mark that we've processed the identifier if this was one
    if (frame.isNotEmpty &&
        frame[0] == SnappyStreamEncoder.chunkTypeStreamIdentifier) {
      _seenIdentifier = true;
    }
    return result;
  }

  @override
  SnappyFormatException createBufferError() => SnappyFormatException(
        'Stream buffer exceeded $maxBufferSize bytes - '
        'frame too large or malformed',
      );

  @override
  SnappyFormatException createMagicError(final List<int> buffer, final int offset) =>
      SnappyFormatException(
        'Expected Snappy stream identifier at offset $offset, '
        'got 0x${buffer[offset].toRadixString(16)}',
      );

  @override
  SnappyFormatException createIncompleteError() =>
      const SnappyFormatException('Incomplete Snappy chunk at end of stream');

  /// Try to parse a single Snappy chunk at offset, return null if incomplete
  ///
  /// This returns each chunk individually for true incremental streaming,
  /// rather than waiting for an entire frame with multiple chunks.
  FrameParseResult? _tryParseChunk(final List<int> buffer, final int offset) {
    // Need at least 4 bytes for chunk header
    if (buffer.length - offset < 4) return null;

    // Parse chunk header
    final length = buffer[offset + 1] |
        (buffer[offset + 2] << 8) |
        (buffer[offset + 3] << 16);

    final chunkSize = 4 + length;

    // Check if we have the complete chunk
    if (buffer.length - offset < chunkSize) return null;

    // Return just this one chunk
    final frame = Uint8List.fromList(buffer.sublist(offset, offset + chunkSize));
    return FrameParseResult(frame, chunkSize);
  }
}
