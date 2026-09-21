import 'dart:typed_data';

/// Represents summary metadata for a saved game slot without needing to deserialize full engine state.
class SaveSlotInfo {
  final int slot;
  final String description;
  final DateTime timestamp;
  final int roomNumber;
  final int score;
  final int maxScore;
  final String filePath;
  final bool exists;
  final Uint8List? thumbnailRgba;

  const SaveSlotInfo({
    required this.slot,
    required this.description,
    required this.timestamp,
    required this.roomNumber,
    required this.score,
    required this.maxScore,
    required this.filePath,
    required this.exists,
    this.thumbnailRgba,
  });

  /// Formatted slot display string (e.g. `Slot 1: In front of castle (Score: 12/210, Room 1)`).
  String get displayName {
    if (!exists) return 'Slot $slot: < Empty >';
    final desc = description.isNotEmpty ? description : 'Room $roomNumber';
    return 'Slot $slot: $desc';
  }

  /// Formatted human-readable date/time string.
  String get formattedDate {
    if (!exists) return '';
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
