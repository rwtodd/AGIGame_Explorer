import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';

/// Contract representing an AGI resource directory.
abstract class ResourceDirectory {
  int get logicCount;
  int get picCount;
  int get viewCount;
  int get soundCount;

  DirEntry findLogic(int number);
  DirEntry findPic(int number);
  DirEntry findView(int number);
  DirEntry findSound(int number);

  List<int> get presentLogicNumbers => [
        for (int i = 0; i < logicCount; i++)
          if (findLogic(i).isPresent) i,
      ];

  List<int> get presentPicNumbers => [
        for (int i = 0; i < picCount; i++)
          if (findPic(i).isPresent) i,
      ];

  List<int> get presentViewNumbers => [
        for (int i = 0; i < viewCount; i++)
          if (findView(i).isPresent) i,
      ];

  List<int> get presentSoundNumbers => [
        for (int i = 0; i < soundCount; i++)
          if (findSound(i).isPresent) i,
      ];

  static ResourceDirectory create(GameMetaData meta) {
    if (meta.isV3) {
      return V3ResourceDirectory.fromGamePath(meta.gamePath, meta.prefix ?? '');
    } else {
      return V2ResourceDirectory.fromGamePath(meta.gamePath);
    }
  }
}

/// Helper to read a file case-insensitively from a directory.
Uint8List _readFileCaseInsensitive(String dirPath, String fileName) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    throw AgiException('Directory does not exist: $dirPath');
  }

  final files = dir.listSync().whereType<File>();
  final target = files.firstWhere(
    (f) => p.basename(f.path).toUpperCase() == fileName.toUpperCase(),
    orElse: () => File(p.join(dirPath, fileName)),
  );

  if (!target.existsSync()) {
    throw AgiException('Required directory file "$fileName" not found in $dirPath');
  }
  return target.readAsBytesSync();
}

/// Helper to extract DirEntry from 3 bytes in a directory table.
DirEntry _lookupItem(Uint8List dir, int byteOffset) {
  if (byteOffset < 0 || byteOffset + 2 >= dir.length) {
    return DirEntry.nonExistent;
  }
  final b0 = dir[byteOffset];
  final b1 = dir[byteOffset + 1];
  final b2 = dir[byteOffset + 2];

  final volnum = (b0 >> 4) & 0x0F;
  final offs = ((b0 & 0x0F) << 16) | (b1 << 8) | b2;
  return DirEntry.of(volnum, offs);
}

/// Resource directory for AGI v1 / v2 games (separate DIR files).
class V2ResourceDirectory extends ResourceDirectory {
  final Uint8List logics;
  final Uint8List pics;
  final Uint8List views;
  final Uint8List sounds;

  V2ResourceDirectory({
    required this.logics,
    required this.pics,
    required this.views,
    required this.sounds,
  });

  factory V2ResourceDirectory.fromGamePath(String gamePath) {
    try {
      final logics = _readFileCaseInsensitive(gamePath, 'LOGDIR');
      final pics = _readFileCaseInsensitive(gamePath, 'PICDIR');
      final views = _readFileCaseInsensitive(gamePath, 'VIEWDIR');
      final sounds = _readFileCaseInsensitive(gamePath, 'SNDDIR');
      return V2ResourceDirectory(
        logics: logics,
        pics: pics,
        views: views,
        sounds: sounds,
      );
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Failed to load V2 resource directory: $e', e);
    }
  }

  @override
  int get logicCount => logics.length ~/ 3;

  @override
  int get picCount => pics.length ~/ 3;

  @override
  int get viewCount => views.length ~/ 3;

  @override
  int get soundCount => sounds.length ~/ 3;

  @override
  DirEntry findLogic(int number) => _lookupItem(logics, number * 3);

  @override
  DirEntry findPic(int number) => _lookupItem(pics, number * 3);

  @override
  DirEntry findView(int number) => _lookupItem(views, number * 3);

  @override
  DirEntry findSound(int number) => _lookupItem(sounds, number * 3);
}

/// Resource directory for AGI v3 games (unified `<prefix>DIR` file).
class V3ResourceDirectory extends ResourceDirectory {
  final Uint8List dir;
  final int logicOffs;
  final int picOffs;
  final int viewOffs;
  final int soundOffs;

  V3ResourceDirectory(this.dir)
      : logicOffs = (dir[0] & 0xFF) | ((dir[1] & 0xFF) << 8),
        picOffs = (dir[2] & 0xFF) | ((dir[3] & 0xFF) << 8),
        viewOffs = (dir[4] & 0xFF) | ((dir[5] & 0xFF) << 8),
        soundOffs = (dir[6] & 0xFF) | ((dir[7] & 0xFF) << 8);

  factory V3ResourceDirectory.fromGamePath(String gamePath, String prefix) {
    try {
      final dirBytes = _readFileCaseInsensitive(gamePath, '${prefix}DIR');
      return V3ResourceDirectory(dirBytes);
    } catch (e) {
      if (e is AgiException) rethrow;
      throw AgiException('Failed to load V3 resource directory: $e', e);
    }
  }

  @override
  int get logicCount => (picOffs - logicOffs) ~/ 3;

  @override
  int get picCount => (viewOffs - picOffs) ~/ 3;

  @override
  int get viewCount => (soundOffs - viewOffs) ~/ 3;

  @override
  int get soundCount => (dir.length - soundOffs) ~/ 3;

  @override
  DirEntry findLogic(int number) =>
      number < logicCount ? _lookupItem(dir, logicOffs + (number * 3)) : DirEntry.nonExistent;

  @override
  DirEntry findPic(int number) =>
      number < picCount ? _lookupItem(dir, picOffs + (number * 3)) : DirEntry.nonExistent;

  @override
  DirEntry findView(int number) =>
      number < viewCount ? _lookupItem(dir, viewOffs + (number * 3)) : DirEntry.nonExistent;

  @override
  DirEntry findSound(int number) =>
      number < soundCount ? _lookupItem(dir, soundOffs + (number * 3)) : DirEntry.nonExistent;
}
