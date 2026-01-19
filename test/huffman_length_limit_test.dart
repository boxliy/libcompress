import 'package:test/test.dart';
import 'package:libcompress/src/util/huffman.dart';

void main() {
  test('computeLimitedCodeLengths caps lengths and assigns all symbols', () {
    const maxBits = 7;
    final frequencies = List<int>.filled(19, 1);
    frequencies[0] = 1000;
    frequencies[1] = 500;

    final lengths =
        HuffmanTreeBuilder.computeLimitedCodeLengths(frequencies, maxBits);

    final nonZero = <int>[];
    for (var i = 0; i < frequencies.length; i++) {
      if (frequencies[i] > 0) {
        nonZero.add(i);
      }
      expect(lengths[i] <= maxBits, isTrue);
    }

    expect(lengths.where((len) => len > 0).length, nonZero.length);

    var slots = 0;
    for (final len in lengths) {
      if (len > 0) {
        slots += 1 << (maxBits - len);
      }
    }
    expect(slots, lessThanOrEqualTo(1 << maxBits));
  });
}
