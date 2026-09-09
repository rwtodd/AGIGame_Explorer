import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/screens/browsers/sci_script_browser_screen.dart';

void main() {
  group('SciScriptBrowserScreen Widget Tests', () {
    late SciVolumeManager vm;

    setUp(() {
      vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    });

    testWidgets('mounts cleanly, displays Decompiled tab, and switches tabs', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SciScriptBrowserScreen(
              initialScriptNumber: 0,
              volumeManager: vm,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify app bar title
      expect(find.text('SCI Script Browser'), findsOneWidget);
      expect(find.text('Script 0'), findsWidgets);

      // Verify tab titles
      expect(find.text('Decompiled'), findsOneWidget);
      expect(find.text('Disassembly'), findsOneWidget);
      expect(find.textContaining('Objects ('), findsOneWidget);
      expect(find.textContaining('Strings ('), findsOneWidget);
      expect(find.text('Exports & Locals'), findsOneWidget);

      // Switch to Disassembly tab
      await tester.tap(find.text('Disassembly'));
      await tester.pumpAndSettle();

      // Verify disassembly contents
      expect(find.byType(ListView), findsWidgets);

      // Switch to Objects tab
      await tester.tap(find.textContaining('Objects ('));
      await tester.pumpAndSettle();

      // PQ object should be listed
      expect(find.text('PQ'), findsWidgets);
      expect(find.text('INSTANCE'), findsWidgets);

      // Switch to Strings tab
      await tester.tap(find.textContaining('Strings ('));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsWidgets);

      // Switch to Exports & Locals tab
      await tester.tap(find.text('Exports & Locals'));
      await tester.pumpAndSettle();
      expect(find.text('Exports Table'), findsOneWidget);
      expect(find.text('Local Variables'), findsOneWidget);
    });

    testWidgets('search filtering and Go to Address dialog work', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SciScriptBrowserScreen(
              initialScriptNumber: 0,
              volumeManager: vm,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query
      final searchInput = find.byType(TextField);
      expect(searchInput, findsOneWidget);
      await tester.enterText(searchInput, 'instance');
      await tester.pumpAndSettle();

      expect(find.textContaining('matches'), findsOneWidget);

      // Clear search
      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      // Open Go to Address dialog
      final navButton = find.byIcon(Icons.navigation);
      expect(navButton, findsOneWidget);
      await tester.tap(navButton);
      await tester.pumpAndSettle();

      expect(find.text('Go to Script Offset'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '0100');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
    });

    testWidgets('switching scripts and history back navigation works', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SciScriptBrowserScreen(
              initialScriptNumber: 0,
              volumeManager: vm,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Click Next Chevron to load next script
      final nextChevron = find.byIcon(Icons.chevron_right);
      expect(nextChevron, findsOneWidget);
      await tester.tap(nextChevron);
      await tester.pumpAndSettle();

      // Click Previous Chevron to go back
      final prevChevron = find.byIcon(Icons.chevron_left);
      expect(prevChevron, findsOneWidget);
      await tester.tap(prevChevron);
      await tester.pumpAndSettle();

      expect(find.text('Script 0'), findsWidgets);
    });
  });
}
