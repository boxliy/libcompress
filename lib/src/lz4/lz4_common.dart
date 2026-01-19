import 'dart:typed_data';

import '../exceptions.dart';
import '../util/xxh32.dart';

// Re-export GrowableBuffer from util
export '../util/growable_buffer.dart' show GrowableBuffer;
// Re-export exception from centralized location
export '../exceptions.dart' show Lz4FormatException;

const int lz4FrameMagic = 0x184D2204;
const int lz4MinMatch = 4;
const int lz4MaxOffset = 0xFFFF;
const int lz4OffsetMask = 0xFFFF;
const int lz4MaxHcProbeAttempts = 256;
const int lz4HashLog = 16;
const int lz4HashTableSize = 1 << lz4HashLog;
const int lz4DefaultBlockSizeCode = 7; // 4 MB
const int lz4DefaultBlockSize = 4 * 1024 * 1024;

/// Standard LZ4 frame block sizes
const int lz4BlockSize64K = 64 * 1024;
const int lz4BlockSize256K = 256 * 1024;
const int lz4BlockSize1M = 1 * 1024 * 1024;
const int lz4BlockSize4M = 4 * 1024 * 1024;

/// Default maximum decompressed size (256 MB)
/// Prevents memory exhaustion from malicious contentSize headers
const int lz4DefaultMaxDecompressedSize = 256 * 1024 * 1024;
// MFLIMIT: Last 5 bytes must be literals to ensure safe decoding
const int lz4MFLimit = 12; // Minimum input size where matches are worth it
const int lz4LastLiterals = 5; // Last bytes that must be literals

int blockSizeFromCode(int code) {
  switch (code) {
    case 4:
      return 64 * 1024;
    case 5:
      return 256 * 1024;
    case 6:
      return 1 * 1024 * 1024;
    case 7:
      return 4 * 1024 * 1024;
    default:
      throw Lz4FormatException('Unsupported block size code: $code');
  }
}

int blockSizeCodeFromSize(int size) {
  if (size <= 64 * 1024) {
    return 4;
  } else if (size <= 256 * 1024) {
    return 5;
  } else if (size <= 1 * 1024 * 1024) {
    return 6;
  } else if (size <= 4 * 1024 * 1024) {
    return 7;
  }
  throw ArgumentError('Unsupported block size for LZ4 frame: $size');
}

int lz4HeaderChecksum(List<int> headerBytes) {
  final checksum = XXH32.hash(Uint8List.fromList(headerBytes));
  return (checksum >> 8) & 0xFF;
}

int lz4ContentChecksum(Uint8List content) {
  return XXH32.hash(content);
}
