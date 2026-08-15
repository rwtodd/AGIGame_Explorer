import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/core/utils/crypto_utils.dart';

/// Contract representing game engine metadata.
abstract class GameMetaData {
  String get versionString;
  double get version;
  String? get prefix;
  String get gamePath;
  List<int> get decryptionKey;

  bool get isV3 => version >= 3.0;
  bool get isBeforeV3 => version < 3.0;

  static double deriveNumericVersion(String versionString) {
    try {
      var s = versionString;
      if (s.length > 5) {
        s = s.substring(0, 5) + s.substring(6);
      }
      return double.parse(s);
    } catch (e) {
      throw AgiException('Extracted bad version number "$versionString"', e);
    }
  }
}

/// Metadata extracted from on-disk game files.
class OnDiskMetaData extends GameMetaData {
  @override
  final String versionString;

  @override
  final double version;

  @override
  final String? prefix;

  @override
  final String gamePath;

  @override
  final List<int> decryptionKey;

  OnDiskMetaData({
    required this.gamePath,
    required this.versionString,
    required this.version,
    this.prefix,
    List<int>? decryptionKey,
  }) : decryptionKey = decryptionKey ?? CryptoUtils.avisDurganKey;

  /// Inspects [gameDir] to extract AGI engine version and V3 prefix.
  static Future<OnDiskMetaData> fromDirectory(String gameDir) async {
    final dir = Directory(gameDir);
    if (!await dir.exists()) {
      throw AgiException('Game directory does not exist: $gameDir');
    }

    final entities = await dir.list().toList();
    final fileNames = entities
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();

    // Look for AGIDATA.OVL (case-insensitive)
    final ovlName = fileNames.firstWhere(
      (name) => name.toUpperCase() == 'AGIDATA.OVL',
      orElse: () => '',
    );

    String versionStr;
    double numericVer;

    if (ovlName.isNotEmpty) {
      final ovlFile = File(p.join(gameDir, ovlName));
      final ovlBytes = await ovlFile.readAsBytes();
      versionStr = extractVersionFromBytes(ovlBytes);
      numericVer = GameMetaData.deriveNumericVersion(versionStr);
    } else {
      // Fallback: check directory structure
      final hasLogDir = fileNames.any((n) => n.toUpperCase() == 'LOGDIR');
      final v3DirFile = fileNames.firstWhere(
        (n) => n.toUpperCase().endsWith('DIR') && n.toUpperCase() != 'LOGDIR' && n.toUpperCase() != 'PICDIR' && n.toUpperCase() != 'VIEWDIR' && n.toUpperCase() != 'SNDDIR',
        orElse: () => '',
      );

      if (v3DirFile.isNotEmpty) {
        versionStr = '3.002.149';
        numericVer = 3.002149;
      } else if (hasLogDir) {
        versionStr = '2.917';
        numericVer = 2.917;
      } else {
        throw const AgiException('Could not identify AGI game files (AGIDATA.OVL, LOGDIR, or <pfx>DIR missing).');
      }
    }

    String? prefixStr;
    if (numericVer >= 3.0) {
      prefixStr = determinePrefix(fileNames);
    }

    return OnDiskMetaData(
      gamePath: gameDir,
      versionString: versionStr,
      version: numericVer,
      prefix: prefixStr,
    );
  }

  /// Synchronous inspection of [gameDir].
  factory OnDiskMetaData.fromDirectorySync(String gameDir) {
    final dir = Directory(gameDir);
    if (!dir.existsSync()) {
      throw AgiException('Game directory does not exist: $gameDir');
    }

    final entities = dir.listSync();
    final fileNames = entities
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();

    final ovlName = fileNames.firstWhere(
      (name) => name.toUpperCase() == 'AGIDATA.OVL',
      orElse: () => '',
    );

    String versionStr;
    double numericVer;

    if (ovlName.isNotEmpty) {
      final ovlFile = File(p.join(gameDir, ovlName));
      final ovlBytes = ovlFile.readAsBytesSync();
      versionStr = extractVersionFromBytes(ovlBytes);
      numericVer = GameMetaData.deriveNumericVersion(versionStr);
    } else {
      final hasLogDir = fileNames.any((n) => n.toUpperCase() == 'LOGDIR');
      final v3DirFile = fileNames.firstWhere(
        (n) => n.toUpperCase().endsWith('DIR') && n.toUpperCase() != 'LOGDIR' && n.toUpperCase() != 'PICDIR' && n.toUpperCase() != 'VIEWDIR' && n.toUpperCase() != 'SNDDIR',
        orElse: () => '',
      );

      if (v3DirFile.isNotEmpty) {
        versionStr = '3.002.149';
        numericVer = 3.002149;
      } else if (hasLogDir) {
        versionStr = '2.917';
        numericVer = 2.917;
      } else {
        throw const AgiException('Could not identify AGI game files (AGIDATA.OVL, LOGDIR, or <pfx>DIR missing).');
      }
    }

    String? prefixStr;
    if (numericVer >= 3.0) {
      prefixStr = determinePrefix(fileNames);
    }

    return OnDiskMetaData(
      gamePath: gameDir,
      versionString: versionStr,
      version: numericVer,
      prefix: prefixStr,
    );
  }

  /// Search the bytes of AGIDATA.OVL for the version number string.
  static String extractVersionFromBytes(Uint8List agidata) {
    final buffer = StringBuffer();
    for (final b in agidata) {
      final len = buffer.length;
      final dotSpot = (len == 1 || len == 5);

      if (dotSpot && (b == 0x2E)) {
        buffer.writeCharCode(b);
      } else if (!dotSpot && (b >= 0x30 && b <= 0x39)) {
        buffer.writeCharCode(b);
        if (len == 8) {
          return buffer.toString();
        }
      } else if (len == 5) {
        return buffer.toString();
      } else {
        buffer.clear();
      }
    }
    throw const AgiException('Reached end of AGIDATA.OVL without finding valid version string.');
  }

  /// Figures out the game prefix (e.g. "KQ4") for V3 games by finding `<prefix>VOL.0` and `<prefix>DIR`.
  static String determinePrefix(List<String> fileNames) {
    for (final name in fileNames) {
      final upper = name.toUpperCase();
      if (upper.endsWith('VOL.0')) {
        final pfx = name.substring(0, name.length - 5);
        final pfxUpper = upper.substring(0, upper.length - 5);
        final hasDir = fileNames.any((n) => n.toUpperCase() == '${pfxUpper}DIR');
        if (hasDir) {
          return pfx;
        }
      }
    }
    throw const AgiException('Could not find matching <prefix>DIR and <prefix>VOL.0 files for V3 game.');
  }
}
