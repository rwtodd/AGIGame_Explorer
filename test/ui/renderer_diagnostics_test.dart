import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_agigame/ui/widgets/game_playfield_widget.dart';
import 'package:flutter_agigame/ui/widgets/renderer_diagnostics.dart';

void main() {
  RendererDiagnostics sample() => RendererDiagnostics(
        renderMode: AgiPictureRenderMode.shaderComposited,
        shaderActive: true,
        windowSize: const Size(800, 600),
        playfieldSize: const Size(640, 480),
        devicePixelRatio: 2.0,
        picNumber: 7,
        strictIntegerScaling: false,
        correctAspectRatio: true,
      );

  group('RendererDiagnostics', () {
    test('describe() reproduces the former badge 4-line format', () {
      expect(
        sample().describe(),
        'PRIORITY SHADER\n'
        'win 800.0x600.0 dpr 2.0 dev 1600x1200\n'
        'pf 640.0x480.0 dev 1280x960\n'
        'scale 2.0000 x 2.4000 pic 7 int off 4:3 on',
      );
    });

    test('describe() reports FALLBACK when the shader is not drawing', () {
      final d = RendererDiagnostics(
        renderMode: AgiPictureRenderMode.shaderComposited,
        shaderActive: false,
        windowSize: const Size(800, 600),
        playfieldSize: const Size(640, 480),
        devicePixelRatio: 1.0,
        picNumber: null,
        strictIntegerScaling: true,
        correctAspectRatio: false,
      );
      expect(d.describe().split('\n').first, 'PRIORITY SHADER: FALLBACK');
      expect(d.describe(), contains('pic null int on 4:3 off'));
    });

    test('scale and device sizes derive from playfield/320x200', () {
      final d = sample();
      expect(d.scaleX, 2.0);
      expect(d.scaleY, 2.4);
      expect(d.deviceWindowSize, const Size(1600, 1200));
      expect(d.devicePlayfieldSize, const Size(1280, 960));
    });

    test('toJson() carries the diagnostics fields', () {
      final json = sample().toJson();
      expect(json['renderMode'], 'shaderComposited');
      expect(json['shaderActive'], isTrue);
      expect(json['scaleX'], 2.0);
      expect(json['picNumber'], 7);
      // Round-trips through JSON encoding cleanly.
      expect(jsonDecode(jsonEncode(json)), json);
    });

    test('value equality supports change detection', () {
      expect(sample(), sample());
      expect(sample().hashCode, sample().hashCode);
      final other = RendererDiagnostics(
        renderMode: AgiPictureRenderMode.compositedSlices,
        shaderActive: true,
        windowSize: const Size(800, 600),
        playfieldSize: const Size(640, 480),
        devicePixelRatio: 2.0,
        picNumber: 7,
        strictIntegerScaling: false,
        correctAspectRatio: true,
      );
      expect(sample(), isNot(other));
    });
  });

  group('injectRendererDiagnostics', () {
    test('returns the snapshot unchanged when diagnostics are null', () {
      final snap = <String, dynamic>{'a': 1};
      expect(identical(injectRendererDiagnostics(snap, null), snap), isTrue);
    });

    test('adds a top-level renderer key when diagnostics are present', () {
      final snap = <String, dynamic>{'a': 1};
      final out = injectRendererDiagnostics(snap, sample());
      expect(out['a'], 1);
      expect(out['renderer'], sample().toJson());
      // Original map is untouched.
      expect(snap, {'a': 1});
    });
  });

  testWidgets('GamePlayfieldWidget publishes diagnostics and shows no badge', (tester) async {
    final engine = AgiGameEngine(speedHz: 20.0);
    addTearDown(engine.dispose);
    final notifier = ValueNotifier<RendererDiagnostics?>(null);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: GamePlayfieldWidget(
            engine: engine,
            renderMode: AgiPictureRenderMode.shaderComposited,
            diagnostics: notifier,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(notifier.value, isNotNull);
    expect(notifier.value!.renderMode, AgiPictureRenderMode.shaderComposited);
    // No picture loaded, so the flat image is not ready.
    expect(notifier.value!.shaderActive, isFalse);
    expect(find.textContaining('PRIORITY SHADER'), findsNothing);
  });
}
