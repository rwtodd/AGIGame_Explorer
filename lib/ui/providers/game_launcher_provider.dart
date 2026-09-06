import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_agigame/domain/game_info.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';

enum LauncherStatus {
  initial,
  scanning,
  loaded,
  error,
}

class LauncherState {
  final LauncherStatus status;
  final String? selectedPath;
  final GameInfo? gameInfo;
  final AgiResourceLoader? loader;
  final SciVolumeManager? sciVolumeManager;
  final String? errorMessage;
  final List<String> recentPaths;

  const LauncherState({
    this.status = LauncherStatus.initial,
    this.selectedPath,
    this.gameInfo,
    this.loader,
    this.sciVolumeManager,
    this.errorMessage,
    this.recentPaths = const [],
  });

  bool get isSci => sciVolumeManager != null;
  bool get isAgi => loader != null;

  LauncherState copyWith({
    LauncherStatus? status,
    String? selectedPath,
    GameInfo? gameInfo,
    AgiResourceLoader? loader,
    SciVolumeManager? sciVolumeManager,
    String? errorMessage,
    List<String>? recentPaths,
  }) {
    return LauncherState(
      status: status ?? this.status,
      selectedPath: selectedPath ?? this.selectedPath,
      gameInfo: gameInfo ?? this.gameInfo,
      loader: loader ?? this.loader,
      sciVolumeManager: sciVolumeManager ?? this.sciVolumeManager,
      errorMessage: errorMessage ?? this.errorMessage,
      recentPaths: recentPaths ?? this.recentPaths,
    );
  }
}

class LauncherNotifier extends Notifier<LauncherState> {
  AgiResourceLoader? _currentAgiLoader;
  SciVolumeManager? _currentSciManager;

  @override
  LauncherState build() {
    ref.onDispose(() {
      _currentAgiLoader?.close();
      _currentAgiLoader = null;
      _currentSciManager?.close();
      _currentSciManager = null;
    });
    return const LauncherState();
  }

  Future<void> pickDirectory() async {
    try {
      final selectedDirectory = await FilePickerPlatform.instance.getDirectoryPath(
        dialogTitle: 'Select Sierra AGI or SCI Game Directory',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await scanDirectory(selectedDirectory);
      }
    } catch (e) {
      state = state.copyWith(
        status: LauncherStatus.error,
        errorMessage: 'Failed to open directory picker: $e',
      );
    }
  }

  Future<void> scanDirectory(String dirPath) async {
    state = state.copyWith(
      status: LauncherStatus.scanning,
      selectedPath: dirPath,
      errorMessage: null,
    );

    try {
      // Close previous engines if open
      _currentAgiLoader?.close();
      _currentAgiLoader = null;
      _currentSciManager?.close();
      _currentSciManager = null;

      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        throw Exception('Directory does not exist: $dirPath');
      }

      final files = dir.listSync().whereType<File>().toList();
      final hasResourceMap = files.any(
        (f) => p.basename(f.path).toUpperCase() == 'RESOURCE.MAP',
      );

      GameInfo gameInfo;
      AgiResourceLoader? agiLoader;
      SciVolumeManager? sciManager;

      if (hasResourceMap) {
        // SCI Game Path
        sciManager = SciVolumeManager.fromDirectory(dirPath);
        _currentSciManager = sciManager;

        final versionStr = _detectSciVersionString(dirPath, files);
        final map = sciManager.resourceMap;

        final picCount = map.entriesForType(SciResourceType.pic).length;
        final viewCount = map.entriesForType(SciResourceType.view).length;
        final scriptCount = map.entriesForType(SciResourceType.script).length;
        final textCount = map.entriesForType(SciResourceType.text).length;
        final soundCount = map.entriesForType(SciResourceType.sound).length;
        final vocabCount = map.entriesForType(SciResourceType.vocab).length;
        final fontCount = map.entriesForType(SciResourceType.font).length;
        final cursorCount = map.entriesForType(SciResourceType.cursor).length;
        final patchCount = map.entriesForType(SciResourceType.patch).length;

        gameInfo = GameInfo(
          gamePath: dirPath,
          versionString: versionStr,
          version: 0.0,
          engineType: SierraEngineType.sci,
          picCount: picCount,
          viewCount: viewCount,
          resourceCounts: {
            'PICTURE Rooms': picCount,
            'VIEW Sprites': viewCount,
            'SCRIPT Bytecode': scriptCount,
            'TEXT Messages': textCount,
            'SOUND Tracks': soundCount,
            'VOCAB Dictionary': vocabCount,
            'FONT Typography': fontCount,
            'CURSOR Sprites': cursorCount,
            'PATCH Driver Fixes': patchCount,
          },
        );
      } else {
        // AGI Game Path
        agiLoader = await AgiResourceLoader.fromDirectory(dirPath);
        _currentAgiLoader = agiLoader;
        gameInfo = agiLoader.toGameInfo();
      }

      final updatedRecents = [
        dirPath,
        ...state.recentPaths.where((p) => p != dirPath),
      ].take(5).toList();

      state = state.copyWith(
        status: LauncherStatus.loaded,
        selectedPath: dirPath,
        gameInfo: gameInfo,
        loader: agiLoader,
        sciVolumeManager: sciManager,
        recentPaths: updatedRecents,
      );
    } catch (e) {
      state = state.copyWith(
        status: LauncherStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  static String _detectSciVersionString(String dirPath, List<File> files) {
    // Check for VERSION file (e.g. QFG2 contains "1.102")
    for (final f in files) {
      if (p.basename(f.path).toUpperCase() == 'VERSION') {
        try {
          final content = f.readAsStringSync().trim();
          if (content.isNotEmpty) {
            if (content.startsWith('1.')) {
              return 'SCI1 EGA (v$content)';
            }
            return 'SCI (v$content)';
          }
        } catch (_) {}
      }
    }

    // Check SCIV.EXE or SIERRA.EXE for version regex
    final exeRegex = RegExp(r'\d\.\d{3}\.\d{3}');
    for (final exeName in ['SCIV.EXE', 'SIERRA.EXE', 'SIERRA.COM']) {
      final file = files.firstWhere(
        (f) => p.basename(f.path).toUpperCase() == exeName,
        orElse: () => File(''),
      );
      if (file.path.isNotEmpty) {
        try {
          final bytes = file.readAsBytesSync();
          final latin1 = String.fromCharCodes(bytes);
          final match = exeRegex.firstMatch(latin1);
          if (match != null) {
            final ver = match.group(0)!;
            if (ver.startsWith('0.')) {
              return 'SCI0 (v$ver)';
            }
            return 'SCI (v$ver)';
          }
        } catch (_) {}
      }
    }

    return 'SCI0';
  }

  void clear() {
    _currentAgiLoader?.close();
    _currentAgiLoader = null;
    _currentSciManager?.close();
    _currentSciManager = null;
    state = state.copyWith(
      status: LauncherStatus.initial,
      selectedPath: null,
      gameInfo: null,
      loader: null,
      sciVolumeManager: null,
      errorMessage: null,
    );
  }
}

final launcherProvider = NotifierProvider<LauncherNotifier, LauncherState>(
  LauncherNotifier.new,
);
