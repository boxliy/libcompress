import 'dart:math' as math;
import 'dart:typed_data';

import '../util/byte_utils.dart';
import '../util/lz77_common.dart';
import 'lz4_common.dart';

class Lz4Encoder {
  Lz4Encoder({
    this.level = 1,
    this.enableContentChecksum = true,
    this.blockSize = lz4DefaultBlockSize,
  }) {
    if (blockSize <= 0) {
      throw ArgumentError.value(blockSize, 'blockSize', 'Must be positive');
    }
  }

  final int level;
  final bool enableContentChecksum;
  final int blockSize;

  Uint8List compress(final Uint8List input) {
    // Estimate output size: header (7-19) + blocks + end mark (4) + checksum (4)
    // Worst case per block: 4-byte header + uncompressed data
    final estimated = 32 + input.length + (input.length ~/ blockSize + 1) * 4;
    final output = Uint8List(estimated);
    var pos = 0;

    // Frame header.
    ByteUtils.writeUint32LEAt(output, pos, lz4FrameMagic);
    pos += 4;

    var flag = 0x40; // Version 01.
    flag |= 0x20; // Independent blocks.
    if (enableContentChecksum) {
      flag |= 0x04;
    }

    final blockSizeCode = blockSizeCodeFromSize(blockSize);
    final bd = blockSizeCode << 4;

    output[pos++] = flag;
    output[pos++] = bd;

    final headerDescriptor = Uint8List.fromList([flag, bd]);
    output[pos++] = lz4HeaderChecksum(headerDescriptor);

    // Reusable buffer for block compression
    final blockBuffer = Uint8List(blockSize + (blockSize ~/ 255) + 16);

    var cursor = 0;
    while (cursor < input.length) {
      final chunkSize = math.min(blockSize, input.length - cursor);
      final chunk = Uint8List.sublistView(input, cursor, cursor + chunkSize);

      final compressedLen = level >= 9
          ? _compressBlockHC(chunk, blockBuffer)
          : _compressBlock(chunk, blockBuffer);
      final useCompressed = compressedLen < chunk.length && chunk.isNotEmpty;

      if (useCompressed) {
        ByteUtils.writeUint32LEAt(output, pos, compressedLen);
        pos += 4;
        output.setRange(pos, pos + compressedLen, blockBuffer);
        pos += compressedLen;
      } else {
        ByteUtils.writeUint32LEAt(output, pos, chunk.length | 0x80000000);
        pos += 4;
        output.setRange(pos, pos + chunk.length, chunk);
        pos += chunk.length;
      }

      cursor += chunkSize;
    }

    // End mark.
    ByteUtils.writeUint32LEAt(output, pos, 0);
    pos += 4;

    if (enableContentChecksum) {
      final checksum = lz4ContentChecksum(input);
      ByteUtils.writeUint32LEAt(output, pos, checksum);
      pos += 4;
    }

    return Uint8List.sublistView(output, 0, pos);
  }

  /// Compresses a block using high-compression mode (level >= 9)
  /// Writes to [out] buffer and returns the number of bytes written.
  int _compressBlockHC(final Uint8List input, final Uint8List out) {
    if (input.isEmpty) {
      out[0] = 0;
      return 1;
    }

    final hashTable = List<int>.filled(lz4HashTableSize, -1);
    final chainTable = List<int>.filled(lz4MaxOffset + 1, -1);
    var op = 0;
    final end = input.length;
    final limit = end - lz4MFLimit;
    final matchLimit = end - lz4LastLiterals;
    var anchor = 0;
    var index = 0;

    while (index <= limit) {
      final hash = LZ77Hash.lz4Hash(input, index, 32 - lz4HashLog);
      final candidate = hashTable[hash];
      hashTable[hash] = index;

      if (index - candidate < lz4MaxOffset) {
        chainTable[index & lz4OffsetMask] = candidate;
      }

      var bestMatchLength = 0;
      var bestMatchOffset = 0;

      var currentCandidate = candidate;
      var attempts = 0;
      while (currentCandidate >= 0 &&
          (index - currentCandidate) < lz4MaxOffset &&
          attempts < lz4MaxHcProbeAttempts) {
        if (currentCandidate + 4 <= input.length &&
            ByteUtils.readUint32LE(input, currentCandidate) ==
                ByteUtils.readUint32LE(input, index)) {
          var matchLength = lz4MinMatch;
          while (index + matchLength < matchLimit &&
              input[index + matchLength] ==
                  input[currentCandidate + matchLength]) {
            matchLength++;
          }

          if (matchLength > bestMatchLength) {
            bestMatchLength = matchLength;
            bestMatchOffset = index - currentCandidate;
          }
        }
        currentCandidate = chainTable[currentCandidate & lz4OffsetMask];
        attempts++;
      }

      if (bestMatchLength < lz4MinMatch) {
        index++;
        continue;
      }

      final matchIndex = index;
      index += bestMatchLength;

      final literalLength = matchIndex - anchor;
      final tokenIndex = op++;

      op = _encodeLiteralLength(out, op, tokenIndex, literalLength);

      if (literalLength > 0) {
        out.setRange(op, op + literalLength, input, anchor);
        op += literalLength;
      }

      ByteUtils.writeUint16LEAt(out, op, bestMatchOffset);
      op += 2;

      op = _encodeMatchLength(out, op, tokenIndex, bestMatchLength);

      anchor = index;
    }

    final remaining = end - anchor;
    if (remaining > 0) {
      final tokenIndex = op++;
      op = _encodeLiteralLength(out, op, tokenIndex, remaining);
      out.setRange(op, op + remaining, input, anchor);
      op += remaining;
    }

    return op;
  }

  /// Compresses a block using standard mode (level < 9)
  /// Writes to [out] buffer and returns the number of bytes written.
  int _compressBlock(final Uint8List input, final Uint8List out) {
    if (input.isEmpty) {
      out[0] = 0;
      return 1;
    }

    final hashTable = List<int>.filled(lz4HashTableSize, -1);
    var op = 0;
    final end = input.length;
    final limit = end - lz4MFLimit;
    final matchLimit = end - lz4LastLiterals;
    var anchor = 0;
    var index = 0;

    while (index <= limit) {
      final hash = LZ77Hash.lz4Hash(input, index, 32 - lz4HashLog);
      final candidate = hashTable[hash];
      hashTable[hash] = index;

      var match = false;
      if (index + lz4MinMatch <= matchLimit &&
          candidate >= 0 &&
          (index - candidate) <= lz4MaxOffset &&
          ByteUtils.readUint32LE(input, candidate) ==
              ByteUtils.readUint32LE(input, index)) {
        match = true;
      }

      if (!match) {
        index++;
        continue;
      }

      final matchIndex = index;

      index += lz4MinMatch;
      var refIndex = candidate + lz4MinMatch;

      while (index < matchLimit && input[index] == input[refIndex]) {
        index++;
        refIndex++;
      }

      final literalLength = matchIndex - anchor;
      final matchLength = index - matchIndex;

      final tokenIndex = op++;

      op = _encodeLiteralLength(out, op, tokenIndex, literalLength);

      if (literalLength > 0) {
        out.setRange(op, op + literalLength, input, anchor);
        op += literalLength;
      }

      final offset = matchIndex - candidate;
      ByteUtils.writeUint16LEAt(out, op, offset);
      op += 2;

      op = _encodeMatchLength(out, op, tokenIndex, matchLength);

      anchor = index;

      if (index - 2 >= 0 && index - 2 <= limit) {
        hashTable[LZ77Hash.lz4Hash(input, index - 2, 32 - lz4HashLog)] =
            index - 2;
      }
      if (index - 1 >= 0 && index - 1 <= limit) {
        hashTable[LZ77Hash.lz4Hash(input, index - 1, 32 - lz4HashLog)] =
            index - 1;
      }
    }

    final remaining = end - anchor;
    if (remaining > 0) {
      final tokenIndex = op++;
      op = _encodeLiteralLength(out, op, tokenIndex, remaining);
      out.setRange(op, op + remaining, input, anchor);
      op += remaining;
    }

    return op;
  }

  /// Encodes literal length into buffer, returns new position after length bytes.
  int _encodeLiteralLength(
    final Uint8List out,
    int pos,
    final int tokenIndex,
    final int literalLength,
  ) {
    final nibble = literalLength < 15 ? literalLength : 15;
    out[tokenIndex] = nibble << 4;
    if (literalLength >= 15) {
      pos = _writeLength(out, pos, literalLength - 15);
    }
    return pos;
  }

  /// Encodes match length into token byte and writes extension bytes.
  /// Returns new position after writing any extension bytes.
  int _encodeMatchLength(
    final Uint8List out,
    int pos,
    final int tokenIndex,
    final int matchLength,
  ) {
    final adjusted = matchLength - lz4MinMatch;
    final nibble = adjusted < 15 ? adjusted : 15;
    out[tokenIndex] |= nibble;
    if (adjusted >= 15) {
      pos = _writeLength(out, pos, adjusted - 15);
    }
    return pos;
  }

  /// Writes extended length bytes, returns new position.
  int _writeLength(final Uint8List out, int pos, int length) {
    while (length >= 255) {
      out[pos++] = 255;
      length -= 255;
    }
    out[pos++] = length;
    return pos;
  }
}
