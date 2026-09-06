import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/ui/screens/browsers/font_browser_screen.dart';

void main() {
  group('FontBrowserScreen', () {
    late SciVolumeManager vm;

    setUp(() {
      vm = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
    });

    testWidgets('loads Font 0, displays glyph grid, inspector, and sandbox', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FontBrowserScreen(
              initialFontNumber: 0,
              volumeManager: vm,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify header
      expect(find.text('FONT 0'), findsOneWidget);
      expect(find.text('SYSFONT / Chicago 12'), findsWidgets);
      expect(find.textContaining('8px Height'), findsOneWidget);
      expect(find.textContaining('128 / 128 Glyphs'), findsOneWidget);

      // Verify panels
      expect(find.text('GLYPH INSPECTION #65 (0x41) \'A\''), findsOneWidget);
      expect(find.text('INTERACTIVE TEXT SANDBOX'), findsOneWidget);
      expect(find.text('METRICS'), findsOneWidget);
      expect(find.text('7 px'), findsWidgets); // Width 7 px of 'A'
      expect(find.text('9 px'), findsWidgets); // Height 9 px of 'A'

      // Select glyph 48 ('0') in the grid
      final glyph48Finder = find.text('48');
      expect(glyph48Finder, findsOneWidget);
      await tester.tap(glyph48Finder);
      await tester.pumpAndSettle();

      // Inspector updates to #48
      expect(find.text('GLYPH INSPECTION #48 (0x30) \'0\''), findsOneWidget);

      // Type custom text into sandbox
      final textField = find.byType(TextField).last;
      await tester.enterText(textField, 'TEST 123');
      await tester.pumpAndSettle();

      // Filter glyphs in search bar
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, '65');
      await tester.pumpAndSettle();
      expect(find.text('65'), findsWidgets);
      // '48' should now be filtered out
      expect(find.text('48'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('48'), findsOneWidget);
    });

    testWidgets('switches fonts via next button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FontBrowserScreen(
              initialFontNumber: 0,
              volumeManager: vm,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('FONT 0'), findsOneWidget);

      // Tap Next Font (chevron right)
      await tester.tap(find.byTooltip('Next Font'));
      await tester.pumpAndSettle();

      // Should now show Font 1
      expect(find.text('FONT 1'), findsOneWidget);
      expect(find.text('USERFONT / New York 12'), findsWidgets);
      expect(find.textContaining('12px Height'), findsOneWidget);
    });
  });
}
