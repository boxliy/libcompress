import 'dart:async';
import 'dart:typed_data';

/// Abstract base class for stream decompression transformers
///
/// Provides the common buffer management, lifecycle handling, and error
/// propagation logic used by all decompression stream transformers.
/// Codec-specific behavior is implemented via abstract methods.
abstract class StreamDecompressTransformer<E extends Exception>
    extends StreamTransformerBase<Uint8List, Uint8List> {
  /// Maximum decompressed size (null = unlimited)
  final int? maxSize;

  /// Maximum buffer size before rejecting input
  final int maxBufferSize;

  /// Creates a stream decompress transformer
  StreamDecompressTransformer({
    this.maxSize,
    required this.maxBufferSize,
  });

  /// Minimum bytes needed to start parsing a frame
  int get minFrameSize;

  /// Validates that buffer has correct magic bytes at the given offset
  bool isValidStart(final List<int> buffer, final int offset);

  /// Attempts to parse a complete frame from the buffer starting at offset
  ///
  /// Returns a [FrameParseResult] with frame data and length if available,
  /// null if more data is needed.
  /// May throw an exception for invalid data that cannot be recovered.
  FrameParseResult? tryParseFrame(final List<int> buffer, final int offset);

  /// Decompresses a complete frame
  Uint8List decompress(final Uint8List frame);

  /// Creates an error for buffer overflow
  E createBufferError();

  /// Creates an error for invalid magic bytes
  E createMagicError(final List<int> buffer, final int offset);

  /// Creates an error for incomplete frame at end of stream
  E createIncompleteError();

  @override
  Stream<Uint8List> bind(final Stream<Uint8List> stream) {
    final controller = StreamController<Uint8List>();
    final buffer = <int>[];
    late StreamSubscription<Uint8List> subscription;

    subscription = stream.listen(
      (chunk) {
        // Check buffer size limit before adding
        if (buffer.length + chunk.length > maxBufferSize) {
          controller.addError(createBufferError());
          subscription.cancel();
          return;
        }
        buffer.addAll(chunk);

        // Try to parse and emit complete frames using cursor
        var cursor = 0;
        while (buffer.length - cursor >= minFrameSize) {
          // Check for valid magic at cursor position
          if (!isValidStart(buffer, cursor)) {
            controller.addError(createMagicError(buffer, cursor));
            subscription.cancel();
            return;
          }

          // Try to find frame boundary
          final result = tryParseFrame(buffer, cursor);
          if (result == null) {
            break; // Need more data
          }

          try {
            final decoded = decompress(result.frame);
            controller.add(decoded);
            cursor += result.length;
          } catch (e) {
            controller.addError(e);
            subscription.cancel();
            return;
          }
        }

        // Remove processed bytes once (O(n) only once per chunk batch)
        if (cursor > 0) {
          buffer.removeRange(0, cursor);
        }
      },
      onError: (e, st) {
        controller.addError(e, st);
        subscription.cancel();
      },
      onDone: () {
        // Check for remaining data using tryParseFrame for validation
        if (buffer.isNotEmpty) {
          if (buffer.length >= minFrameSize) {
            // Use tryParseFrame to validate the frame is complete
            final result = tryParseFrame(buffer, 0);
            if (result != null && result.length == buffer.length) {
              try {
                final decoded = decompress(result.frame);
                controller.add(decoded);
              } catch (e) {
                controller.addError(e);
              }
            } else {
              controller.addError(createIncompleteError());
            }
          } else {
            controller.addError(createIncompleteError());
          }
        }
        controller.close();
      },
      cancelOnError: true,
    );

    // Wire up controller lifecycle for proper cleanup
    controller.onCancel = subscription.cancel;

    return controller.stream;
  }
}

/// Result of parsing a frame from a buffer
class FrameParseResult {
  /// The frame data
  final Uint8List frame;

  /// The total length consumed from the buffer (may differ from frame.length
  /// for codecs that transform or filter data during parsing)
  final int length;

  const FrameParseResult(this.frame, this.length);
}
