/// Base exception for all AGI engine and resource loader errors.
class AgiException implements Exception {
  final String message;
  final Object? cause;

  const AgiException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'AgiException: $message (Cause: $cause)';
    }
    return 'AgiException: $message';
  }
}

/// Thrown when a requested resource index is not present in the directory.
class ResourceNotPresentException extends AgiException {
  const ResourceNotPresentException(super.message, [super.cause]);
}

/// Thrown when a resource file or stream contains corrupt or unparseable data.
class CorruptResourceException extends AgiException {
  const CorruptResourceException(super.message, [super.cause]);
}
