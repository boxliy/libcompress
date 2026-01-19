import 'dart:typed_data';

import '../exceptions.dart';

// Re-export exception from centralized location
export '../exceptions.dart' show DeflateFormatException;

/// DEFLATE compression algorithm constants and shared utilities
///
/// Implements the DEFLATE compression format as specified in RFC 1951.
/// Used by GZIP, ZIP, PNG, and other formats.

/// Maximum size of the LZ77 sliding window (32KB)
const int windowSize = 32768;

/// Maximum match distance (same as window size)
const int maxDistance = 32768;

/// Minimum match length for LZ77
const int minMatch = 3;

/// Maximum match length for LZ77
const int maxMatch = 258;

/// Hash table size for match finding (must be power of 2)
const int hashSize = 1 << 15; // 32K entries

/// Hash shift amount
const int hashShift = 5;

/// Number of bits for length codes
const int lengthCodes = 29;

/// Number of literal/length codes (0-285)
const int literals = 256;

/// Number of distance codes (0-29)
const int distanceCodes = 30;

/// Number of bit length codes (0-18)
const int bitLengthCodes = 19;

/// End-of-block symbol
const int endBlock = 256;

/// DEFLATE block types
enum BlockType {
  /// No compression (stored block)
  stored(0),

  /// Compressed with fixed Huffman codes
  fixedHuffman(1),

  /// Compressed with dynamic Huffman codes
  dynamicHuffman(2);

  final int value;
  const BlockType(this.value);
}

/// Length code base values for encoding match lengths
const List<int> lengthBase = [
  3, 4, 5, 6, 7, 8, 9, 10, // codes 257-264
  11, 13, 15, 17, // codes 265-268
  19, 23, 27, 31, // codes 269-272
  35, 43, 51, 59, // codes 273-276
  67, 83, 99, 115, // codes 277-280
  131, 163, 195, 227, // codes 281-284
  258, // code 285
];

/// Extra bits for length codes
const List<int> lengthExtraBits = [
  0, 0, 0, 0, 0, 0, 0, 0, // 257-264
  1, 1, 1, 1, // 265-268
  2, 2, 2, 2, // 269-272
  3, 3, 3, 3, // 273-276
  4, 4, 4, 4, // 277-280
  5, 5, 5, 5, // 281-284
  0, // 285
];

/// Distance code base values
const List<int> distanceBase = [
  1, 2, 3, 4, // codes 0-3
  5, 7, // codes 4-5
  9, 13, // codes 6-7
  17, 25, // codes 8-9
  33, 49, // codes 10-11
  65, 97, // codes 12-13
  129, 193, // codes 14-15
  257, 385, // codes 16-17
  513, 769, // codes 18-19
  1025, 1537, // codes 20-21
  2049, 3073, // codes 22-23
  4097, 6145, // codes 24-25
  8193, 12289, // codes 26-27
  16385, 24577, // codes 28-29
];

/// Extra bits for distance codes
const List<int> distanceExtraBits = [
  0, 0, 0, 0, // 0-3
  1, 1, // 4-5
  2, 2, // 6-7
  3, 3, // 8-9
  4, 4, // 10-11
  5, 5, // 12-13
  6, 6, // 14-15
  7, 7, // 16-17
  8, 8, // 18-19
  9, 9, // 20-21
  10, 10, // 22-23
  11, 11, // 24-25
  12, 12, // 26-27
  13, 13, // 28-29
];

/// Order of code length codes (for encoding Huffman trees)
const List<int> codeLengthOrder = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
];

/// Computes hash value for LZ77 match finding
int hash(Uint8List data, int pos) {
  if (pos + 2 >= data.length) return 0;
  return ((data[pos] << (hashShift * 2)) ^
          (data[pos + 1] << hashShift) ^
          data[pos + 2]) &
      (hashSize - 1);
}

/// Encodes a length value into length code and extra bits
///
/// Throws [ArgumentError] if length is not between [minMatch] and [maxMatch].
LengthCode encodeLength(int length) {
  if (length < minMatch || length > maxMatch) {
    throw ArgumentError.value(
      length,
      'length',
      'Must be between $minMatch and $maxMatch',
    );
  }

  if (length < 11) {
    return LengthCode(257 + length - 3, 0, 0);
  }

  for (var code = 0; code < lengthBase.length - 1; code++) {
    if (length < lengthBase[code + 1]) {
      final extra = length - lengthBase[code];
      return LengthCode(257 + code, lengthExtraBits[code], extra);
    }
  }

  // Length 258
  return LengthCode(285, 0, 0);
}

/// Encodes a distance value into distance code and extra bits
DistanceCode encodeDistance(int distance) {
  if (distance < 1 || distance > maxDistance) {
    throw DeflateFormatException('Invalid distance: $distance (must be 1-$maxDistance)');
  }

  if (distance <= 4) {
    return DistanceCode(distance - 1, 0, 0);
  }

  // Check codes 4-28
  for (var code = 4; code < 29; code++) {
    if (distance < distanceBase[code + 1]) {
      final extra = distance - distanceBase[code];
      return DistanceCode(code, distanceExtraBits[code], extra);
    }
  }

  // Code 29 handles distances 24577-32768
  final extra = distance - distanceBase[29];
  return DistanceCode(29, distanceExtraBits[29], extra);
}

/// Represents an encoded length with code and extra bits
class LengthCode {
  final int code;
  final int extraBits;
  final int extraValue;

  const LengthCode(this.code, this.extraBits, this.extraValue);
}

/// Represents an encoded distance with code and extra bits
class DistanceCode {
  final int code;
  final int extraBits;
  final int extraValue;

  const DistanceCode(this.code, this.extraBits, this.extraValue);
}

/// Represents a literal or length/distance pair in LZ77
sealed class Token {}

/// A literal byte token
class LiteralToken extends Token {
  final int value;
  LiteralToken(this.value);
}

/// A length/distance match token
class MatchToken extends Token {
  final int length;
  final int distance;
  MatchToken(this.length, this.distance);
}
