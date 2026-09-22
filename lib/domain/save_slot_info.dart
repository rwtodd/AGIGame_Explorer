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

  /// Pixel size of [thumbnailRgba]. AGI saves are 80×84; SCI saves are 80×50.
  final int? thumbnailWidth;
  final int? thumbnailHeight;

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
    this.thumbnailWidth,
    this.thumbnailHeight,
  });

  /// Known thumbnail buffers: AGI 160×168 scaled to 80×84, SCI 320×200 to 80×50.
  static (int width, int height)? inferThumbnailSize(int byteLength) {
    const known = <(int, int)>[
      (80, 50),
      (80, 84),
    ];
    for (final size in known) {
      if (byteLength == size.$1 * size.$2 * 4) return size;
    }
    return null;
  }

  /// Prefers explicit JSON dimensions when they match [thumb]; otherwise infers.
  static (int width, int height)? thumbnailSizeFromJson(
    Map<dynamic, dynamic> json,
    Uint8List? thumb,
  ) {
    final w = (json['thumbnailWidth'] as num?)?.toInt();
    final h = (json['thumbnailHeight'] as num?)?.toInt();
    if (thumb != null && w != null && h != null && w > 0 && h > 0 && w * h * 4 == thumb.length) {
      return (w, h);
    }
    if (thumb == null) return null;
    return inferThumbnailSize(thumb.length);
  }

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
