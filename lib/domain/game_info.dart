/// The Sierra adventure game engine generation.
enum SierraEngineType {
  agi,
  sci,
}

/// High-level summary of an inspected Sierra (AGI or SCI) game directory.
class GameInfo {
  final String gamePath;
  final String versionString;
  final double version;
  final String? prefix;
  final SierraEngineType engineType;
  final Map<String, int> resourceCounts;

  // AGI-specific fields (0 for SCI games)
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
    this.engineType = SierraEngineType.agi,
    this.resourceCounts = const {},
    this.logicCount = 0,
    this.picCount = 0,
    this.viewCount = 0,
    this.soundCount = 0,
    this.objectCount = 0,
    this.wordCount = 0,
    this.maxAnimatedObjects = 0,
  });

  bool get isSci => engineType == SierraEngineType.sci;
  bool get isAgi => engineType == SierraEngineType.agi;

  bool get isV3 => version >= 3.0;

  String get displayName {
    if (prefix != null && prefix!.isNotEmpty) {
      return prefix!;
    }
    final segments = gamePath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      final raw = segments.last;
      return raw
          .replaceAll('-', ' ')
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
    }
    return isSci ? 'SCI Game' : 'AGI Game';
  }
}
