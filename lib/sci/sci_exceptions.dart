/// Base exception for all SCI engine and resource loader errors.
class SciException implements Exception {
  final String message;
  final Object? cause;

  const SciException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'SciException: $message (Cause: $cause)';
    }
    return 'SciException: $message';
  }
}

/// Thrown when a requested SCI resource (type and number) cannot be found
/// in either the resource map or the loose patch directory.
class SciResourceNotFoundException extends SciException {
  const SciResourceNotFoundException(super.message, [super.cause]);
}

/// Thrown when a resource map, volume header, or resource file contains corrupt
/// or malformed binary structures.
class SciCorruptResourceException extends SciException {
  const SciCorruptResourceException(super.message, [super.cause]);
}

/// Thrown when decompression (LZW, Huffman, etc.) fails due to corrupt bitstream,
/// invalid codes, or output length mismatch.
class SciDecompressionException extends SciException {
  const SciDecompressionException(super.message, [super.cause]);
}
