import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/sierra_cursor.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/screens/browsers/cursor_browser_screen.dart';

void main() {
  group('CursorBrowserScreen widget tests', () {
    late SciVolumeManager vm;

    setUp(() {
      vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    });

    testWidgets('loads PQ2 cursors, displays Cursor 999 by default with metrics and gallery', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: CursorBrowserScreen(volumeManager: vm),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify AppBar details
      expect(find.text('CURSOR 999'), findsOneWidget);
      expect(find.text(SierraCursor.standardCursorName(999)), findsWidgets);
      expect(find.text('16×16 • Hotspot: (0, 0)'), findsOneWidget);

      // Verify Cursor Gallery shows both PQ2 cursors
      expect(find.text('AVAILABLE CURSORS (2)'), findsOneWidget);
      expect(find.text('Cursor 999'), findsOneWidget);
      expect(find.text('Cursor 997'), findsOneWidget);
      expect(find.text('DEFAULT'), findsOneWidget); // Default tag on 999

      // Verify Pixel Inspector is present
      expect(find.text('PIXEL INSPECTOR'), findsOneWidget);
      expect(find.text('RESOURCE METRICS'), findsOneWidget);
      expect(find.text('Size: 68 bytes'), findsOneWidget);

      // Verify Live Testing Sandbox is present
      expect(find.text('LIVE MOUSE TESTING SANDBOX'), findsOneWidget);
      expect(find.text('Click Target'), findsOneWidget);
      expect(find.text('Locker Keys'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
    });

    testWidgets('switches to Cursor 997 when selected in gallery', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: CursorBrowserScreen(volumeManager: vm),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Cursor 997 card
      await tester.tap(find.text('Cursor 997'));
      await tester.pumpAndSettle();

      // Verify AppBar now shows CURSOR 997
      expect(find.text('CURSOR 997'), findsOneWidget);
      expect(find.text(SierraCursor.standardCursorName(997)), findsWidgets);
    });

    testWidgets('interacts with sandbox targets and click counters', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: CursorBrowserScreen(volumeManager: vm),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click on "Click Target"
      expect(find.text('Score: 0'), findsOneWidget);
      await tester.tap(find.text('Click Target'));
      await tester.pumpAndSettle();
      expect(find.text('Score: 1'), findsOneWidget);

      // Click on "Locker Keys" item
      expect(find.text('Locker Keys'), findsOneWidget);
      await tester.tap(find.text('Locker Keys'));
      await tester.pumpAndSettle();
      expect(find.text('Keys Collected'), findsOneWidget);

      // Click on Door
      expect(find.text('CLOSED'), findsOneWidget);
      await tester.tap(find.text('CLOSED'));
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
    });
  });
}
