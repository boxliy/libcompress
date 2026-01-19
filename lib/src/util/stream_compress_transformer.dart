import 'dart:async';
import 'dart:typed_data';

/// Generic compression stream transformer
///
/// Handles buffer management and chunking for streaming compression.
/// The actual compression is performed by the provided [compress] callback.
class StreamCompressTransformer
    extends StreamTransformerBase<Uint8List, Uint8List> {
  /// Size threshold for emitting compressed chunks
  final int chunkSize;

  /// Callback to compress a chunk of data
  final Uint8List Function(Uint8List data) compress;

  /// Optional callback for first chunk (e.g., stream headers)
  final Uint8List Function()? header;

  /// Creates a compression stream transformer
  ///
  /// [chunkSize] determines when buffered data is compressed and emitted.
  /// [compress] is called for each chunk to perform the actual compression.
  /// [header] if provided, is called once before the first compressed chunk.
  StreamCompressTransformer({
    required this.chunkSize,
    required this.compress,
    this.header,
  });

  @override
  Stream<Uint8List> bind(final Stream<Uint8List> stream) {
    final controller = StreamController<Uint8List>();
    final buffer = <int>[];
    var cursor = 0; // Track consumed position to avoid O(n²) removeRange
    var wroteHeader = false;

    stream.listen(
      (chunk) {
        buffer.addAll(chunk);

        // Process complete chunks using cursor (O(1) per chunk)
        while (buffer.length - cursor >= chunkSize) {
          final data = Uint8List.fromList(
              buffer.sublist(cursor, cursor + chunkSize));
          cursor += chunkSize;

          if (!wroteHeader && header != null) {
            controller.add(header!());
            wroteHeader = true;
          }
          controller.add(compress(data));
        }

        // Compact buffer when cursor exceeds threshold (amortized O(n))
        if (cursor > 0 && (cursor >= buffer.length ~/ 2 || cursor >= 8192)) {
          buffer.removeRange(0, cursor);
          cursor = 0;
        }
      },
      onError: controller.addError,
      onDone: () {
        // Process remaining data after cursor
        final remaining = buffer.length - cursor;
        if (remaining > 0) {
          if (!wroteHeader && header != null) {
            controller.add(header!());
          }
          controller.add(compress(Uint8List.fromList(
              buffer.sublist(cursor, buffer.length))));
        } else if (!wroteHeader && header != null) {
          // Empty input but header required
          controller.add(header!());
        }
        controller.close();
      },
      cancelOnError: true,
    );

    return controller.stream;
  }
}
