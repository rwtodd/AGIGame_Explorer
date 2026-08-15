/// High-level summary of an inspected AGI game directory.
class GameInfo {
  final String gamePath;
  final String versionString;
  final double version;
  final String? prefix;
  final int logicCount;
  final int picCount;
  final int viewCount;
  final int soundCount;
  final int objectCount;
  final int wordCount;
  final int maxAnimatedObjects;

  const GameInfo({
    required this.gamePath,
    required this.versionString,
    required this.version,
    this.prefix,
    required this.logicCount,
    required this.picCount,
    required this.viewCount,
    required this.soundCount,
    required this.objectCount,
    required this.wordCount,
    required this.maxAnimatedObjects,
  });

  bool get isV3 => version >= 3.0;

  String get displayName {
    if (prefix != null && prefix!.isNotEmpty) {
      return prefix!;
    }
    final segments = gamePath.split(RegExp(r'[/\\]'));
    return segments.isNotEmpty ? segments.last : 'AGI Game';
  }
}
