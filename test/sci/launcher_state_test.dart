import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

void main() {
  test('copyWith can null the unused engine after SCI→AGI', () {
    final vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    final sciState = const LauncherState().copyWith(
      status: LauncherStatus.loaded,
      sciVolumeManager: vm,
    );
    expect(sciState.isSci, isTrue);

    final agiState = sciState.copyWith(
      loader: null,
      sciVolumeManager: null,
    );
    expect(agiState.isSci, isFalse);
    expect(agiState.loader, isNull);
    expect(agiState.sciVolumeManager, isNull);
  });
}
