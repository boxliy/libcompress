import 'dart:math' as math;
import 'dart:typed_data';

import '../util/byte_utils.dart';
import '../util/xxh32.dart';
import 'lz4_common.dart';

class Lz4Decoder {
  /// Maximum allowed decompressed size (prevents OOM attacks)
  /// Set to null for unlimited (not recommended for untrusted input)
  final int? maxSize;

  /// Creates a decoder with optional size limit
  ///
  /// [maxSize] defaults to [lz4DefaultMaxDecompressedSize] (256MB).
  /// Set to null to allow unlimited output (use with trusted input only).
  Lz4Decoder({this.maxSize = lz4DefaultMaxDecompressedSize});

  Uint8List decompress(Uint8List input) {
    if (input.isEmpty) {
      return Uint8List(0);
    }

    final reader = _FrameReader(input);

    final magic = reader.readUint32();
    if (magic != lz4FrameMagic) {
      throw Lz4FormatException(
        'Invalid LZ4 frame magic: 0x${magic.toRadixString(16)}',
      );
    }

    final flag = reader.readByte();
    final version = flag >> 6;
    if (version != 0x01) {
      throw Lz4FormatException('Unsupported LZ4 frame version $version');
    }
    if ((flag & 0x02) != 0) {
      throw Lz4FormatException('Reserved bit set in LZ4 FLG byte');
    }

    final blockIndependence = (flag & 0x20) != 0;
    final blockChecksumFlag = (flag & 0x10) != 0;
    final contentSizeFlag = (flag & 0x08) != 0;
    final contentChecksumFlag = (flag & 0x04) != 0;
    final dictIdFlag = (flag & 0x01) != 0;
    final bd = reader.readByte();
    final blockMaxSizeCode = (bd >> 4) & 0x07;
    final blockMaxSize = blockSizeFromCode(blockMaxSizeCode);
    if (!blockIndependence) {
      throw Lz4FormatException('Dependent blocks are not supported');
    }

    final headerBytes = <int>[flag, bd];

    int? expectedContentSize;
    if (contentSizeFlag) {
      final sizeBytes = reader.readBytes(8);
      headerBytes.addAll(sizeBytes);
      var contentSize = 0;
      for (var i = 0; i < 8; i++) {
        contentSize |= sizeBytes[i] << (8 * i);
      }
      expectedContentSize = contentSize;

      // Validate declared content size against limit early
      if (maxSize != null && contentSize > maxSize!) {
        throw Lz4FormatException(
          'Declared content size $contentSize exceeds '
          'maximum allowed size $maxSize',
        );
      }
    }

    if (dictIdFlag) {
      final dictBytes = reader.readBytes(4);
      headerBytes.addAll(dictBytes);
      final dictId = ByteUtils.readUint32LE(dictBytes, 0);
      if (dictId != 0) {
        throw Lz4FormatException('External dictionaries are not supported');
      }
    }

    final headerChecksum = reader.readByte();
    final expectedHeaderChecksum = lz4HeaderChecksum(headerBytes);
    if (headerChecksum != expectedHeaderChecksum) {
      throw Lz4FormatException('Invalid LZ4 header checksum');
    }

    var initialCapacity = expectedContentSize != null
        ? math.max(256, math.min(expectedContentSize, blockMaxSize * 2))
        : blockMaxSize;
    if (maxSize != null && initialCapacity > maxSize!) {
      initialCapacity = maxSize!;
    }
    final output = GrowableBuffer(initialCapacity, maxSize);
    final blockDecoder = _BlockDecoder(output);

    while (true) {
      final blockSizeField = reader.readUint32();
      if (blockSizeField == 0) {
        break;
      }

      final isCompressed = (blockSizeField & 0x80000000) == 0;
      final blockSize = blockSizeField & 0x7FFFFFFF;

      if (blockSize > blockMaxSize) {
        throw Lz4FormatException(
          'Block size $blockSize exceeds maximum $blockMaxSize',
        );
      }

      final blockBytes = reader.readBytes(blockSize);

      if (blockChecksumFlag) {
        final expectedBlockChecksum = reader.readUint32();
        final actualBlockChecksum = XXH32.hash(blockBytes);
        if (expectedBlockChecksum != actualBlockChecksum) {
          throw Lz4FormatException('Block checksum mismatch');
        }
      }

      if (!isCompressed) {
        output.addBytes(blockBytes, 0, blockBytes.length);
      } else {
        blockDecoder.reset(blockBytes);
        blockDecoder.decode();
      }
    }

    final decompressed = output.toBytes();

    if (contentChecksumFlag) {
      final expectedContentChecksum = reader.readUint32();
      final actualContentChecksum = lz4ContentChecksum(decompressed);
      if (expectedContentChecksum != actualContentChecksum) {
        throw Lz4FormatException('Content checksum mismatch');
      }
    }

    if (!reader.isAtEnd) {
      throw Lz4FormatException('Trailing bytes after LZ4 frame');
    }

    if (expectedContentSize != null &&
        decompressed.length != expectedContentSize) {
      throw Lz4FormatException(
        'Decompressed size ${decompressed.length} != expected $expectedContentSize',
      );
    }

    return decompressed;
  }
}

class _FrameReader {
  _FrameReader(Uint8List data) : _data = data;

  final Uint8List _data;
  int _offset = 0;

  int readByte() {
    if (_offset >= _data.length) {
      throw Lz4FormatException('Unexpected end of input');
    }
    return _data[_offset++];
  }

  Uint8List readBytes(int length) {
    if (_offset + length > _data.length) {
      throw Lz4FormatException('Unexpected end of input');
    }
    final bytes = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return bytes;
  }

  int readUint32() {
    final bytes = readBytes(4);
    return ByteUtils.readUint32LE(bytes, 0);
  }

  bool get isAtEnd => _offset == _data.length;
}

class _BlockDecoder {
  _BlockDecoder(this._output);

  final GrowableBuffer _output;
  late Uint8List _block;

  void reset(Uint8List block) {
    _block = block;
  }

  void decode() {
    var index = 0;
    final limit = _block.length;

    while (index < limit) {
      final token = _block[index++];

      // Literal length.
      var literalLength = token >> 4;
      if (literalLength == 15) {
        var complete = false;
        while (index < limit) {
          final value = _block[index++];
          literalLength += value;
          if (value != 255) {
            complete = true;
            break;
          }
        }
        if (!complete) {
          throw Lz4FormatException(
            'Unexpected end while reading literal length extension',
          );
        }
      }

      if (literalLength > 0) {
        if (index + literalLength > limit) {
          throw Lz4FormatException('Literal length exceeds block size');
        }
        _output.addBytes(_block, index, literalLength);
        index += literalLength;
      }

      if (index >= limit) {
        break;
      }

      if (index + 1 >= limit) {
        throw Lz4FormatException('Truncated offset in block');
      }
      final offset = ByteUtils.readUint16LE(_block, index);
      index += 2;

      // Per LZ4 spec: offset 0 is invalid and must be rejected to prevent
      // information disclosure (reading uninitialized buffer content)
      if (offset == 0) {
        throw Lz4FormatException(
            'Invalid match offset: 0 (offset must be at least 1)');
      }
      if (offset > _output.length) {
        throw Lz4FormatException(
            'Invalid match offset: $offset exceeds output length ${_output.length}');
      }

      var matchLength = token & 0x0F;
      if (matchLength == 15) {
        var complete = false;
        while (index < limit) {
          final value = _block[index++];
          matchLength += value;
          if (value != 255) {
            complete = true;
            break;
          }
        }
        if (!complete) {
          throw Lz4FormatException(
              'Unexpected end while reading match length extension');
        }
      }
      matchLength += lz4MinMatch;

      _output.copyFromHistory(offset, matchLength);
    }

    if (index != limit) {
      throw Lz4FormatException('Block was not fully decoded');
    }
  }
}
