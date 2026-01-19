/// Bit manipulation helpers used across compression codecs.
///
/// Provides utilities for counting bits and working with integer bit patterns
/// without relying on platform intrinsics.
class BitMath {
  /// Returns the index (0-based) of the highest set bit in [value].
  ///
  /// Throws [ArgumentError] if [value] is zero or negative.
  static int highBit32(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'Must be positive');
    }
    return value.bitLength - 1;
  }
}
