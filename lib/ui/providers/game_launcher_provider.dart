import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/domain/game_info.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

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
  final String? errorMessage;
  final List<String> recentPaths;

  const LauncherState({
    this.status = LauncherStatus.initial,
    this.selectedPath,
    this.gameInfo,
    this.loader,
    this.errorMessage,
    this.recentPaths = const [],
  });

  LauncherState copyWith({
    LauncherStatus? status,
    String? selectedPath,
    GameInfo? gameInfo,
    AgiResourceLoader? loader,
    String? errorMessage,
    List<String>? recentPaths,
  }) {
    return LauncherState(
      status: status ?? this.status,
      selectedPath: selectedPath ?? this.selectedPath,
      gameInfo: gameInfo ?? this.gameInfo,
      loader: loader ?? this.loader,
      errorMessage: errorMessage ?? this.errorMessage,
      recentPaths: recentPaths ?? this.recentPaths,
    );
  }
}

class LauncherNotifier extends Notifier<LauncherState> {
  AgiResourceLoader? _currentLoader;

  @override
  LauncherState build() {
    ref.onDispose(() {
      _currentLoader?.close();
      _currentLoader = null;
    });
    return const LauncherState();
  }

  Future<void> pickDirectory() async {
    try {
      final selectedDirectory = await FilePickerPlatform.instance.getDirectoryPath(
        dialogTitle: 'Select Sierra AGI Game Directory',
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
      // Close previous loader if open
      _currentLoader?.close();

      final loader = await AgiResourceLoader.fromDirectory(dirPath);
      _currentLoader = loader;
      final gameInfo = loader.toGameInfo();

      final updatedRecents = [
        dirPath,
        ...state.recentPaths.where((p) => p != dirPath),
      ].take(5).toList();

      state = state.copyWith(
        status: LauncherStatus.loaded,
        selectedPath: dirPath,
        gameInfo: gameInfo,
        loader: loader,
        recentPaths: updatedRecents,
      );
    } catch (e) {
      state = state.copyWith(
        status: LauncherStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void clear() {
    _currentLoader?.close();
    _currentLoader = null;
    state = state.copyWith(
      status: LauncherStatus.initial,
      selectedPath: null,
      gameInfo: null,
      loader: null,
      errorMessage: null,
    );
  }
}

final launcherProvider = NotifierProvider<LauncherNotifier, LauncherState>(
  LauncherNotifier.new,
);
