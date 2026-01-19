import 'dart:typed_data';

/// XXH64 hash algorithm implementation.
///
/// This is a fast, non-cryptographic hash function that produces a 64-bit hash.
/// Based on the XXHash specification: https://github.com/Cyan4973/xxHash
class XXH64 {
  // XXH64 constants
  static const int _prime1 = 0x9E3779B185EBCA87;
  static const int _prime2 = 0xC2B2AE3D27D4EB4F;
  static const int _prime3 = 0x165667B19E3779F9;
  static const int _prime4 = 0x85EBCA77C2B2AE63;
  static const int _prime5 = 0x27D4EB2F165667C5;

  /// Computes the XXH64 hash of the given data with an optional seed.
  ///
  /// [data] - The input data to hash
  /// [seed] - Optional seed value (default: 0)
  /// Returns the 64-bit hash as an unsigned integer
  static int hash(Uint8List data, [int seed = 0]) {
    final length = data.length;
    int h64;
    int index = 0;

    if (length >= 32) {
      final limit = length - 32;
      int v1 = _add64(seed, _add64(_prime1, _prime2));
      int v2 = _add64(seed, _prime2);
      int v3 = seed;
      int v4 = _sub64(seed, _prime1);

      while (index <= limit) {
        v1 = _round64(v1, _readLittleEndian64(data, index));
        index += 8;
        v2 = _round64(v2, _readLittleEndian64(data, index));
        index += 8;
        v3 = _round64(v3, _readLittleEndian64(data, index));
        index += 8;
        v4 = _round64(v4, _readLittleEndian64(data, index));
        index += 8;
      }

      h64 = _add64(
        _add64(
          _add64(_rotateLeft64(v1, 1), _rotateLeft64(v2, 7)),
          _add64(_rotateLeft64(v3, 12), _rotateLeft64(v4, 18)),
        ),
        0,
      );

      h64 = _mergeRound64(h64, v1);
      h64 = _mergeRound64(h64, v2);
      h64 = _mergeRound64(h64, v3);
      h64 = _mergeRound64(h64, v4);
    } else {
      h64 = _add64(seed, _prime5);
    }

    h64 = _add64(h64, length);

    // Process remaining bytes in 8-byte chunks
    while (index <= length - 8) {
      int k1 = _readLittleEndian64(data, index);
      k1 = _mult64(k1, _prime2);
      k1 = _rotateLeft64(k1, 31);
      k1 = _mult64(k1, _prime1);

      h64 ^= k1;
      h64 = _add64(_mult64(_rotateLeft64(h64, 27), _prime1), _prime4);
      index += 8;
    }

    // Process remaining bytes in 4-byte chunks
    while (index <= length - 4) {
      int k1 = _readLittleEndian32(data, index);
      k1 = _mult64(k1, _prime1);
      h64 ^= k1;
      h64 = _add64(_mult64(_rotateLeft64(h64, 23), _prime2), _prime3);
      index += 4;
    }

    // Process remaining bytes individually
    while (index < length) {
      final k1 = _mult64(data[index], _prime5);
      h64 ^= k1;
      h64 = _mult64(_rotateLeft64(h64, 11), _prime1);
      index++;
    }

    // Final avalanche
    h64 ^= h64 >>> 33;
    h64 = _mult64(h64, _prime2);
    h64 ^= h64 >>> 29;
    h64 = _mult64(h64, _prime3);
    h64 ^= h64 >>> 32;

    return h64;
  }

  /// Computes XXH64 hash of a list of integers (treating each as a byte).
  static int hashFromList(List<int> data, [int seed = 0]) {
    return hash(Uint8List.fromList(data), seed);
  }

  static int _add64(int a, int b) {
    return (a + b) & 0xFFFFFFFFFFFFFFFF;
  }

  static int _sub64(int a, int b) {
    return (a - b) & 0xFFFFFFFFFFFFFFFF;
  }

  static int _mult64(int a, int b) {
    return (a * b) & 0xFFFFFFFFFFFFFFFF;
  }

  static int _round64(int acc, int input) {
    acc = _add64(acc, _mult64(input, _prime2));
    acc = _rotateLeft64(acc, 31);
    acc = _mult64(acc, _prime1);
    return acc;
  }

  static int _mergeRound64(int acc, int val) {
    val = _mult64(val, _prime2);
    val = _rotateLeft64(val, 31);
    val = _mult64(val, _prime1);

    acc ^= val;
    acc = _add64(_mult64(acc, _prime1), _prime4);
    return acc;
  }

  static int _rotateLeft64(int value, int amount) {
    value &= 0xFFFFFFFFFFFFFFFF;
    return ((value << amount) | (value >>> (64 - amount))) & 0xFFFFFFFFFFFFFFFF;
  }

  static int _readLittleEndian32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _readLittleEndian64(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24) |
        (data[offset + 4] << 32) |
        (data[offset + 5] << 40) |
        (data[offset + 6] << 48) |
        (data[offset + 7] << 56);
  }
}
