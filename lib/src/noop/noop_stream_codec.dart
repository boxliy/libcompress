import 'dart:async';
import 'dart:typed_data';

import '../compression_stream_codec.dart';

/// Pass-through streaming codec that performs no compression
///
/// Useful for testing streaming pipelines, benchmarking, and as a
/// placeholder when compression is optional.
class NoopStreamCodec extends CompressionStreamCodec {
  @override
  String get name => 'NOOP';

  @override
  Stream<Uint8List> compress(final Stream<Uint8List> input) => input;

  @override
  Stream<Uint8List> decompress(final Stream<Uint8List> input) => input;
}
