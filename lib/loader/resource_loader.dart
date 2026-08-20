import 'dart:typed_data';
import 'package:flutter_agigame/core/errors/agi_exceptions.dart';
import 'package:flutter_agigame/domain/agi_view.dart';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/domain/game_info.dart';
import 'package:flutter_agigame/domain/inventory_object.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/loader/game_metadata.dart';
import 'package:flutter_agigame/loader/parsers/logic_parser.dart';
import 'package:flutter_agigame/loader/parsers/objects_parser.dart';
import 'package:flutter_agigame/loader/parsers/sound_parser.dart';
import 'package:flutter_agigame/loader/parsers/view_parser.dart';
import 'package:flutter_agigame/loader/parsers/words_parser.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';
import 'package:flutter_agigame/picture/pic_vector_interpreter.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';

/// Central resource loader for Sierra AGI games (v2 and v3).
class AgiResourceLoader {
  final GameMetaData meta;
  final ResourceDirectory rdir;
  final VolumeManager vmgr;
  final AgiDictionary dictionary;
  final List<AgiObject> initialObjects;
  final int maxAnimated;
  final LruCache<int, AgiView> _viewCache;
  final LruCache<int, AgiLogicScript> _logicCache;
  final LruCache<int, AgiPic> _picCache;

  AgiResourceLoader._({
    required this.meta,
    required this.rdir,
    required this.vmgr,
    required this.dictionary,
    required this.initialObjects,
    required this.maxAnimated,
    int viewCacheCapacity = 64,
    int logicCacheCapacity = 64,
    int picCacheCapacity = 32,
  })  : _viewCache = LruCache<int, AgiView>(viewCacheCapacity),
        _logicCache = LruCache<int, AgiLogicScript>(logicCacheCapacity),
        _picCache = LruCache<int, AgiPic>(picCacheCapacity);

  /// Creates an [AgiResourceLoader] with explicit [ResourceDirectory] and [VolumeManager] (useful for testing).
  factory AgiResourceLoader.custom({
    required GameMetaData meta,
    required ResourceDirectory rdir,
    required VolumeManager vmgr,
  }) {
    AgiDictionary dict;
    try {
      dict = WordsParser.parse(vmgr.getWordsData());
    } catch (e) {
      throw AgiException('Failed to load WORDS.TOK: $e', e);
    }

    ParsedObjects parsedObs;
    try {
      final isEncrypted = meta.version >= 2.411;
      parsedObs = ObjectsParser.parse(
        vmgr.getObjectsData(),
        isEncrypted: isEncrypted,
        key: meta.decryptionKey,
      );
    } catch (e) {
      throw AgiException('Failed to load OBJECT file: $e', e);
    }

    return AgiResourceLoader._(
      meta: meta,
      rdir: rdir,
      vmgr: vmgr,
      dictionary: dict,
      initialObjects: parsedObs.objects,
      maxAnimated: parsedObs.maxAnimated,
    );
  }

  /// Creates an [AgiResourceLoader] for the specified [meta], automatically constructing
  /// the appropriate directory and volume manager.
  factory AgiResourceLoader.fromMetaData(GameMetaData meta) {
    final rdir = ResourceDirectory.create(meta);
    final vmgr = VolumeManager.create(meta);
    return AgiResourceLoader.custom(
      meta: meta,
      rdir: rdir,
      vmgr: vmgr,
    );
  }

  /// Convenience loader directly from a game folder path.
  static Future<AgiResourceLoader> fromDirectory(String gameDir) async {
    final meta = await OnDiskMetaData.fromDirectory(gameDir);
    return AgiResourceLoader.fromMetaData(meta);
  }

  /// Synchronous loader directly from a game folder path.
  factory AgiResourceLoader.fromDirectorySync(String gameDir) {
    final meta = OnDiskMetaData.fromDirectorySync(gameDir);
    return AgiResourceLoader.fromMetaData(meta);
  }

  int get soundCount => rdir.soundCount;
  int get picCount => rdir.picCount;
  int get viewCount => rdir.viewCount;
  int get logicCount => rdir.logicCount;
  int get objectCount => initialObjects.length;
  int get wordCount => dictionary.wordCount;

  List<int> get presentPicNumbers => rdir.presentPicNumbers;
  List<int> get presentViewNumbers => rdir.presentViewNumbers;
  List<int> get presentLogicNumbers => rdir.presentLogicNumbers;
  List<int> get presentSoundNumbers => rdir.presentSoundNumbers;

  /// Loads raw uncompressed bytes for a SOUND resource.
  Uint8List loadRawSound(int number) {
    final de = rdir.findSound(number);
    if (!de.isPresent) {
      throw ResourceNotPresentException('Sound resource $number is not present.');
    }
    return vmgr.getResource(de);
  }

  /// Loads and parses a SOUND resource into an [AgiSound].
  AgiSound loadSound(int number) {
    final rawData = loadRawSound(number);
    return SoundParser.parse(rawData);
  }

  /// Loads raw uncompressed bytes for a PICTURE resource.
  Uint8List loadRawPic(int number) {
    final de = rdir.findPic(number);
    if (!de.isPresent) {
      throw ResourceNotPresentException('Pic resource $number is not present.');
    }
    return vmgr.getResource(de);
  }

  /// Loads and interprets an AGI PICTURE resource into an [AgiPic] with priority slices.
  /// Uses cached base vector raster buffers to make repeated room entries instantaneous.
  AgiPic loadPic(int number) {
    final cached = _picCache.get(number);
    if (cached != null) {
      final visualCopy = Uint8List.fromList(cached.visualPixels);
      final priCopy = cached.priorityBuffer.clone();
      final slices = PictureSlicer.slice(
        visualPixels: visualCopy,
        priorityBuffer: priCopy,
      );
      return AgiPic(
        picNumber: number,
        visualPixels: visualCopy,
        priorityBuffer: priCopy,
        slices: slices,
      );
    }

    final rawBytes = loadRawPic(number);
    final interpreter = PicVectorInterpreter(isV3: meta.isV3);
    final pic = interpreter.interpret(rawBytes);
    pic.picNumber = number;

    // Cache unmutated template buffers
    final visualTemplate = Uint8List.fromList(pic.visualPixels);
    final priTemplate = pic.priorityBuffer.clone();
    _picCache.put(
      number,
      AgiPic(
        picNumber: number,
        visualPixels: visualTemplate,
        priorityBuffer: priTemplate,
        slices: const {},
      ),
    );

    return pic;
  }

  /// Loads raw uncompressed bytes for a VIEW resource.
  Uint8List loadRawView(int number) {
    final de = rdir.findView(number);
    if (!de.isPresent) {
      throw ResourceNotPresentException('View resource $number is not present.');
    }
    return vmgr.getResource(de);
  }

  /// Loads and parses a VIEW resource into an [AgiView], with memory caching.
  AgiView loadView(int number) {
    final cached = _viewCache.get(number);
    if (cached != null) {
      return cached;
    }
    final raw = loadRawView(number);
    final view = ViewParser.parse(raw, viewNumber: number);
    _viewCache.put(number, view);
    return view;
  }

  /// Asynchronously loads and parses a VIEW resource into an [AgiView], with memory caching.
  Future<AgiView> loadViewAsync(int number) async {
    final cached = _viewCache.get(number);
    if (cached != null) {
      return cached;
    }
    final de = rdir.findView(number);
    if (!de.isPresent) {
      throw ResourceNotPresentException('View resource $number is not present.');
    }
    final raw = await vmgr.getResourceAsync(de);
    final view = ViewParser.parse(raw, viewNumber: number);
    _viewCache.put(number, view);
    return view;
  }

  /// Loads raw uncompressed bytes for a LOGIC resource.
  Uint8List loadRawLogic(int number) {
    final de = rdir.findLogic(number);
    if (!de.isPresent) {
      throw ResourceNotPresentException('Logic resource $number is not present.');
    }
    return vmgr.getResource(de);
  }

  /// Loads and parses a [AgiLogicScript] for LOGIC resource [number], with memory caching.
  AgiLogicScript loadLogic(int number) {
    final cached = _logicCache.get(number);
    if (cached != null) {
      return cached;
    }
    final raw = loadRawLogic(number);
    final isEncrypted = meta.version < 3.0;
    final script = LogicParser.parse(
      raw,
      isEncrypted: isEncrypted,
      key: meta.decryptionKey,
      logicNumber: number,
    );
    _logicCache.put(number, script);
    return script;
  }

  /// Summarizes current loaded game into a [GameInfo] snapshot.
  GameInfo toGameInfo() {
    return GameInfo(
      gamePath: meta.gamePath,
      versionString: meta.versionString,
      version: meta.version,
      prefix: meta.prefix,
      logicCount: logicCount,
      picCount: picCount,
      viewCount: viewCount,
      soundCount: soundCount,
      objectCount: objectCount,
      wordCount: wordCount,
      maxAnimatedObjects: maxAnimated,
    );
  }

  void close() {
    _viewCache.clear();
    _logicCache.clear();
    _picCache.clear();
    vmgr.close();
  }
}
