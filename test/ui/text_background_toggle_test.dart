import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/domain/text_screen_buffer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/screens/game/game_screen.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  group('Render Black Text Backgrounds Setting & Compositing', () {
    test('AgiDisplaySettings serializes and deserializes renderBlackTextBackgrounds', () {
      const defaultSettings = AgiDisplaySettings();
      expect(defaultSettings.renderBlackTextBackgrounds, isFalse);

      final customSettings = defaultSettings.copyWith(renderBlackTextBackgrounds: true);
      expect(customSettings.renderBlackTextBackgrounds, isTrue);

      final json = customSettings.toJson();
      expect(json['renderBlackTextBackgrounds'], isTrue);

      final parsed = AgiDisplaySettings.fromJson(json);
      expect(parsed.renderBlackTextBackgrounds, isTrue);
    });

    test('AgiTextScreenBuffer marks space cells as isWritten and paints background', () {
      final buffer = AgiTextScreenBuffer();
      buffer.writeString(5, 10, 'A B C', fg: 15, bg: 0);

      // 'A' at col 10, ' ' at col 11, 'B' at col 12, ' ' at col 13, 'C' at col 14
      expect(buffer.getCell(5, 10).isWritten, isTrue);
      expect(buffer.getCell(5, 11).isWritten, isTrue);
      expect(buffer.getCell(5, 11).char, ' ');
      expect(buffer.getCell(5, 12).isWritten, isTrue);
      expect(buffer.getCell(5, 13).isWritten, isTrue);
      expect(buffer.getCell(5, 13).char, ' ');
      expect(buffer.getCell(5, 14).isWritten, isTrue);

      // Col 15 was not written
      expect(buffer.getCell(5, 15).isWritten, isFalse);

      final painterOpaque = AgiPicturePainter(
        textScreenBuffer: buffer,
        renderBlackTextBackgrounds: true,
        playfieldRow: 1,
      );

      final recorderOpaque = ui.PictureRecorder();
      final canvasOpaque = Canvas(recorderOpaque);
      painterOpaque.paint(canvasOpaque, const Size(320, 200));
      final picOpaque = recorderOpaque.endRecording();
      expect(picOpaque, isNotNull);
    });

    testWidgets('GameScreen video options panel toggles Render Black Text Backgrounds', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final engine = AgiGameEngine();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: GameScreen(
              engine: engine,
              initialSettings: const AgiUserSettings(
                display: AgiDisplaySettings(
                  renderBlackTextBackgrounds: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open Video Options in Sidebar
      await tester.tap(find.byTooltip('Display & Video Options'));
      await tester.pumpAndSettle();

      // Verify the switch tile exists
      expect(find.text('Render Black Text Backgrounds'), findsOneWidget);
      expect(find.text('Render transparent text background (modern clean look)'), findsOneWidget);

      // Toggle switch to ON
      await tester.tap(find.text('Render Black Text Backgrounds'));
      await tester.pumpAndSettle();

      // Should now show DOS/BIOS description
      expect(find.text('Draw authentic solid black box behind text characters (DOS/BIOS style)'), findsOneWidget);

      engine.dispose();
    });
  });
}
