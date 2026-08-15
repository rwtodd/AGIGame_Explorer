import 'dart:typed_data';

/// Encodes 16-bit signed PCM audio samples into a standard RIFF WAVE (.wav) container.
class WavEncoder {
  const WavEncoder._();

  /// Creates a complete `.wav` file as [Uint8List] from interleaved 16-bit signed PCM [samples].
  ///
  /// [sampleRate]: Typically 44100 or 48000.
  /// [numChannels]: 1 for Mono, 2 for Stereo.
  static Uint8List encode({
    required Int16List samples,
    required int sampleRate,
    int numChannels = 2,
  }) {
    if (numChannels != 1 && numChannels != 2) {
      throw ArgumentError('numChannels must be 1 (mono) or 2 (stereo)');
    }

    final dataSize = samples.length * 2;
    final totalSize = 44 + dataSize;
    final byteData = ByteData(totalSize);

    // RIFF Chunk Descriptor
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    byteData.setUint8(8, 0x57);  // 'W'
    byteData.setUint8(9, 0x41);  // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // "fmt " sub-chunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * numChannels * 2, Endian.little); // ByteRate
    byteData.setUint16(32, numChannels * 2, Endian.little);              // BlockAlign
    byteData.setUint16(34, 16, Endian.little);                            // BitsPerSample

    // "data" sub-chunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, dataSize, Endian.little);

    // Copy PCM sample bytes
    final resultBytes = byteData.buffer.asUint8List();
    final sampleBytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    resultBytes.setRange(44, totalSize, sampleBytes);

    return resultBytes;
  }
}
