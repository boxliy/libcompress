## 1.0.0

- Initial release with pure Dart compression implementations
- **LZ4**: Full frame format support with configurable block sizes (64K, 256K, 1M, 4M) and compression levels 1-9 (HC mode)
- **Snappy**: Raw block format and streaming (framing) format with CRC32C checksums
- **GZIP**: Pure Dart DEFLATE implementation with compression levels 1-9, optional filename/comment metadata
- **Zstd**: Full RFC 8878 implementation with FSE/Huffman entropy coding, sequence encoding, repeat offsets, and compression levels 1-22
- Stream-based APIs for all codecs via `CompressionStreamCodec`
- Common codec interface via `CompressionCodec` and `CodecFactory`
- Security: All decompressors enforce configurable `maxDecompressedSize` limits
- CLI tool for compression/decompression with all codecs
- CLI compatibility verified with lz4, gzip, snzip, and zstd tools
