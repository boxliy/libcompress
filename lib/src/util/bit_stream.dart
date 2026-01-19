import 'dart:typed_data';

/// A writer for creating a stream of bits.
///
/// Bits are written from a value's LSB to MSB, and packed into bytes
/// starting from the LSB of each byte.
class BitStreamWriter {
  final _builder = BytesBuilder();
  int _bitBuffer = 0;
  int _bitCount = 0;

  /// Writes a value with a specific number of bits to the stream.
  void writeBits(int value, int bitCount) {
    if (bitCount < 0 || bitCount > 32) {
      throw ArgumentError('bitCount must be between 0 and 32');
    }
    _bitBuffer |= (value & ((1 << bitCount) - 1)) << _bitCount;
    _bitCount += bitCount;

    while (_bitCount >= 8) {
      _builder.addByte(_bitBuffer & 0xFF);
      _bitBuffer >>= 8;
      _bitCount -= 8;
    }
  }

  /// Flushes any remaining bits in the current byte and aligns the
  /// writer to the next byte boundary.
  void flushToByte() {
    if (_bitCount > 0) {
      _builder.addByte(_bitBuffer & 0xFF);
      _bitBuffer = 0;
      _bitCount = 0;
    }
  }

  /// Returns the written bits as a byte list, flushing any remaining bits.
  Uint8List toBytes() {
    if (_bitCount == 0) {
      return _builder.toBytes();
    }
    // Add pending bits and return
    _builder.addByte(_bitBuffer & 0xFF);
    final result = _builder.toBytes();
    // Note: This modifies _builder state, so toBytes() is not idempotent
    return result;
  }
}

/// A reader for consuming a stream of bits from a byte list.
///
/// Bits are read in the same order they are written by [BitStreamWriter].
/// Uses a simple byte-at-a-time approach for reliable byte alignment.
class BitStreamReader {
  final Uint8List _data;
  int _bytePos = 0;
  int _bitPos = 0; // Bit position within current byte (0-7)
  int _lastReadValue = 0;
  int _lastReadBits = 0;

  BitStreamReader(this._data);

  /// Returns the current byte position in the stream
  int get bytePosition => _bytePos;

  /// Returns the current bit offset within the current byte (0-7)
  int get bitOffset => _bitPos;

  /// Returns true if all bits from the underlying data have been consumed.
  ///
  /// Note: [consumeBits] normalizes position so _bitPos is always 0-7.
  /// When all bits are consumed, _bytePos == _data.length and _bitPos == 0.
  bool get isEndOfStream => _bytePos >= _data.length;

  /// Reads a single byte from the stream.
  int readByte() {
    return readBits(8);
  }

  /// Reads an unsigned 16-bit integer from the stream.
  int readUint16() {
    return readBits(16);
  }

  /// Reads a specific number of bytes from the stream.
  ///
  /// This method requires the stream to be byte-aligned. Call [flushToByte]
  /// if the alignment is uncertain.
  Uint8List readBytes(int length) {
    if (_bitPos != 0) {
      throw StateError(
        'Cannot read bytes on a non-byte-aligned position. Call flushToByte() first.',
      );
    }
    if (_bytePos + length > _data.length) {
      throw ArgumentError(
        'Read of $length bytes exceeds available data of ${_data.length - _bytePos} bytes.',
      );
    }
    final result = _data.sublist(_bytePos, _bytePos + length);
    _bytePos += length;
    return result;
  }

  /// Reads a value with a specific number of bits from the stream.
  int readBits(int numBits, {bool reuseLast = false}) {
    if (numBits < 0 || numBits > 32) {
      throw ArgumentError('numBits must be between 0 and 32');
    }

    if (numBits == 0) return 0;

    if (reuseLast && _lastReadBits >= numBits) {
      return _lastReadValue & ((1 << numBits) - 1);
    }

    final result = peekBits(numBits);
    consumeBits(numBits);

    _lastReadValue = result;
    _lastReadBits = numBits;
    return result;
  }

  /// Peeks at a value with a specific number of bits without advancing the stream.
  int peekBits(int bitCount) {
    if (bitCount < 0 || bitCount > 32) {
      throw ArgumentError('bitCount must be between 0 and 32');
    }

    if (bitCount == 0) return 0;

    var result = 0;
    var bitsRead = 0;
    var bytePos = _bytePos;
    var bitPos = _bitPos;

    while (bitsRead < bitCount) {
      if (bytePos >= _data.length) {
        throw StateError('Not enough bits in stream to peek');
      }

      final currentByte = _data[bytePos];
      final bitsAvailableInByte = 8 - bitPos;
      final bitsToRead = bitCount - bitsRead;
      final bitsFromThisByte = bitsToRead < bitsAvailableInByte ? bitsToRead : bitsAvailableInByte;

      // Extract bits from current byte (starting at bitPos)
      final mask = (1 << bitsFromThisByte) - 1;
      final bits = (currentByte >> bitPos) & mask;

      result |= bits << bitsRead;
      bitsRead += bitsFromThisByte;
      bitPos += bitsFromThisByte;

      if (bitPos >= 8) {
        bytePos++;
        bitPos = 0;
      }
    }

    return result;
  }

  /// Advances the stream position by a specific number of bits.
  void consumeBits(int bitCount) {
    if (bitCount < 0) {
      throw ArgumentError('bitCount cannot be negative');
    }

    _bitPos += bitCount;
    while (_bitPos >= 8) {
      _bytePos++;
      _bitPos -= 8;
    }

    if (_bytePos > _data.length ||
        (_bytePos == _data.length && _bitPos > 0)) {
      throw StateError('Not enough bits in stream to consume');
    }
  }

  /// Discards any remaining bits in the current byte and aligns the
  /// reader to the next byte boundary.
  void flushToByte() {
    if (_bitPos > 0) {
      _bytePos++;
      _bitPos = 0;
    }
  }

  /// Creates a new [BitStreamReader] that reads a specific number of bytes
  /// from the current stream's position, and advances this stream's position
  /// past those bytes.
  BitStreamReader substream(int length) {
    if (_bitPos != 0) {
      throw StateError(
        'Cannot create a substream on a non-byte-aligned position. Call flushToByte() first.',
      );
    }
    if (_bytePos + length > _data.length) {
      throw ArgumentError(
        'Substream length of $length exceeds available data of ${_data.length - _bytePos} bytes.',
      );
    }
    final sublist = _data.sublist(_bytePos, _bytePos + length);
    _bytePos += length;
    return BitStreamReader(sublist);
  }
}
