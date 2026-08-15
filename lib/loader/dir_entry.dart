/// Represents the location of an AGI resource inside a VOL file.
class DirEntry {
  final int volume;
  final int offset;

  const DirEntry(this.volume, this.offset);

  static const DirEntry nonExistent = DirEntry(0x0F, 0xFFFFF);

  /// Returns true if this entry points to a real, present resource.
  bool get isPresent => !(volume == 0x0F && offset == 0xFFFFF);

  static DirEntry of(int volume, int offset) {
    if (volume == 0x0F && offset == 0xFFFFF) {
      return nonExistent;
    }
    return DirEntry(volume, offset);
  }

  @override
  String toString() {
    if (isPresent) {
      return 'Volume $volume, Offset 0x${offset.toRadixString(16).toUpperCase()} ($offset)';
    }
    return 'Not Present';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirEntry &&
          runtimeType == other.runtimeType &&
          volume == other.volume &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(volume, offset);
}
