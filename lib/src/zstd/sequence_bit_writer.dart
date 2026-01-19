import 'dart:typed_data';

/// Bit writer for sequence encoding
///
/// Zstandard sequences use a backward bitstream that is read from end to beginning.
/// To support this, we accumulate all bits, then reverse the byte order.
class SequenceBitWriter {
  int _bitBuffer = 0;
  int _bitsInBuffer = 0;
  final _bytes = <int>[];

  /// Write specified number of bits in little-endian order
  ///
  /// Bits are accumulated LSB-first in a buffer and flushed to bytes when full.
  void writeBits(int value, int count) {
    if (count <= 0) return;

    // Accumulate bits at current position
    _bitBuffer |= (value & ((1 << count) - 1)) << _bitsInBuffer;
    _bitsInBuffer += count;

    // Flush complete bytes to output
    while (_bitsInBuffer >= 8) {
      _bytes.add(_bitBuffer & 0xFF);
      _bitBuffer >>= 8;
      _bitsInBuffer -= 8;
    }
  }

  /// Convert accumulated bits to bytes
  ///
  /// Does NOT reverse byte order.
  /// Result: [First Written ... Last Written].
  Uint8List toBytes() {
    if (_bitsInBuffer > 0) {
      _bytes.add(_bitBuffer & ((1 << _bitsInBuffer) - 1));
    }

    // Return bytes in forward order
    return Uint8List.fromList(allBytes);
  }

  List<int> get allBytes => _bytes;

  int get bitCount => _bytes.length * 8 + _bitsInBuffer;
}
