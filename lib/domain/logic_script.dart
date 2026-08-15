import 'dart:typed_data';

/// Represents a parsed Sierra AGI LOGIC resource containing bytecode instructions
/// and an array of null-terminated message strings.
class AgiLogicScript {
  /// The logic resource number, if known (e.g. 0 for LOGIC.0).
  final int? logicNumber;

  /// The raw bytecode instructions.
  final Uint8List bytecodes;

  /// The list of message strings associated with this script.
  /// Note: AGI scripts reference messages with 1-based indexing (`%m1` is index 0).
  final List<String> messages;

  const AgiLogicScript({
    required this.bytecodes,
    required this.messages,
    this.logicNumber,
  });

  /// Retrieves message by 1-based message number `%m<num>`.
  /// Returns empty string if out of range.
  String getMessage(int num) {
    if (num > 0 && num <= messages.length) {
      return messages[num - 1];
    }
    return '';
  }

  /// Total count of messages defined in this logic resource.
  int get messageCount => messages.length;

  /// Length of the bytecode section in bytes.
  int get bytecodeLength => bytecodes.length;
}
