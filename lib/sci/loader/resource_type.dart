/// SCI resource types across SCI0, SCI01, and SCI1-EGA.
///
/// Integer values correspond to Sierra's 5-bit resource types (0x00 - 0x14).
enum SciResourceType {
  view(0, 'view', 'v16'),
  pic(1, 'pic', 'p16'),
  script(2, 'script', 'scr'),
  text(3, 'text', 'tex'),
  sound(4, 'sound', 'snd'),
  memory(5, 'memory', 'mem'),
  vocab(6, 'vocab', 'voc'),
  font(7, 'font', 'fon'),
  cursor(8, 'cursor', 'cur'),
  patch(9, 'patch', 'pat'),
  bitmap(10, 'bitmap', 'bit'),
  palette(11, 'palette', 'pal'),
  cdAudio(12, 'cdaudio', 'cda'),
  audio(13, 'audio', 'aud'),
  sync(14, 'sync', 'syn'),
  message(15, 'message', 'msg'),
  map(16, 'map', 'map'),
  heap(17, 'heap', 'hep'),
  audio36(18, 'audio36', 'a36'),
  sync36(19, 'sync36', 's36'),
  translation(20, 'translation', 'trn');

  final int typeCode;
  final String typeName;
  final String primaryExtension;

  const SciResourceType(this.typeCode, this.typeName, this.primaryExtension);

  /// Resolves an integer type code (0..20) into a [SciResourceType].
  /// Masked with 0x7F to handle high-bit flags (e.g. 0x82 for script patch).
  static SciResourceType? fromInt(int value) {
    final clean = value & 0x7F;
    if (clean >= 0 && clean < values.length) {
      return values[clean];
    }
    return null;
  }

  /// Tries to resolve a resource type by its name or common file extension (case-insensitive).
  static SciResourceType? fromString(String nameOrExt) {
    final lower = nameOrExt.toLowerCase();
    for (final t in values) {
      if (t.name.toLowerCase() == lower ||
          t.typeName.toLowerCase() == lower ||
          t.primaryExtension.toLowerCase() == lower) {
        return t;
      }
    }
    // Check aliases
    switch (lower) {
      case 'scr':
        return SciResourceType.script;
      case 'tex':
        return SciResourceType.text;
      case 'snd':
        return SciResourceType.sound;
      case 'voc':
        return SciResourceType.vocab;
      case 'fon':
        return SciResourceType.font;
      case 'cur':
        return SciResourceType.cursor;
      case 'pat':
        return SciResourceType.patch;
      case 'pal':
        return SciResourceType.palette;
      case 'aud':
        return SciResourceType.audio;
      case 'msg':
        return SciResourceType.message;
      case 'hep':
        return SciResourceType.heap;
      default:
        return null;
    }
  }
}

/// Identifies a unique SCI resource by its [type] and numeric index [number].
class SciResourceId implements Comparable<SciResourceId> {
  final SciResourceType type;
  final int number;

  const SciResourceId(this.type, this.number);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SciResourceId &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          number == other.number;

  @override
  int get hashCode => Object.hash(type, number);

  @override
  int compareTo(SciResourceId other) {
    final typeCmp = type.typeCode.compareTo(other.type.typeCode);
    if (typeCmp != 0) return typeCmp;
    return number.compareTo(other.number);
  }

  @override
  String toString() => '${type.typeName}.$number';
}
