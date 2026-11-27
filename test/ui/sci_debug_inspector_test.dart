// Stage 7: SciDebugInspectorDialog Audio tab widget tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/widgets/sci_debug_inspector_dialog.dart';

void main() {
  group('SciDebugInspectorDialog Audio tab (Stage 7)', () {
    late SciGameEngine engine;

    setUp(() {
      engine = SciGameEngine(volumeManager: SciVolumeManager.empty());
      engine.pause();
    });

    tearDown(() {
      engine.dispose();
    });

    testWidgets('Audio tab renders no-bank/no-source state without crashing',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SciDebugInspectorDialog(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Audio'), findsOneWidget);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Captured snapshot (explicit capture only)'), findsOneWidget);
      expect(find.text('SUMMARY'), findsOneWidget);
      expect(find.textContaining('no bank'), findsWidgets);
      expect(find.textContaining('no active source'), findsWidgets);
      expect(find.text('PATCH BROWSER'), findsOneWidget);
      expect(find.text('LIVE CONTROLS (session debug overrides, applied next note, not persisted)'),
          findsOneWidget);
      expect(find.text('Reset overrides'), findsOneWidget);
      expect(find.text('Track Pan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('WRITE TRACE'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('WRITE TRACE'), findsOneWidget);
      expect(find.text('No active source: write trace is unavailable.'), findsOneWidget);
      // Patch audition controls are in an empty state: no Play button yet
      // (only shown when a bank is available).
      expect(find.text('Play'), findsNothing);
      expect(find.byType(Slider), findsWidgets);
    });
  });
}
