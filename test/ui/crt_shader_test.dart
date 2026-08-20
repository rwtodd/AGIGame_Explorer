import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/constants/ega_colors.dart';
import 'package:flutter_agigame/domain/picture.dart';
import 'package:flutter_agigame/domain/priority_buffer.dart';
import 'package:flutter_agigame/picture/picture_slicer.dart';
import 'package:flutter_agigame/ui/shaders/crt_shader_loader.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrtShaderLoader Tests', () {
    setUp(() {
      CrtShaderLoader.resetForTesting();
    });

    test('initial state is uninitialized with null program', () {
      expect(CrtShaderLoader.program, isNull);
      expect(CrtShaderLoader.isReady, isFalse);
    });

    test('initialize loads and compiles FragmentProgram asset successfully', () async {
      final program = await CrtShaderLoader.initialize();
      expect(program, isNotNull);
      expect(CrtShaderLoader.isReady, isTrue);
      expect(CrtShaderLoader.program, same(program));
    });
  });

  group('CrtShaderOverlayPainter Tests', () {
    test('instantiates with default parameters', () {
      const painter = CrtShaderOverlayPainter();
      expect(painter.scanlineIntensity, equals(0.22));
      expect(painter.vignetteIntensity, equals(0.35));
      expect(painter.curvature, equals(0.05));
      expect(painter.phosphorIntensity, equals(1.0));
    });

    test('shouldRepaint responds to parameter changes', () {
      const p1 = CrtShaderOverlayPainter(scanlineIntensity: 0.2);
      const p2 = CrtShaderOverlayPainter(scanlineIntensity: 0.2);
      const p3 = CrtShaderOverlayPainter(scanlineIntensity: 0.5);
      const p4 = CrtShaderOverlayPainter(vignetteIntensity: 0.8);
      const p5 = CrtShaderOverlayPainter(curvature: 0.1);
      const p6 = CrtShaderOverlayPainter(phosphorIntensity: 0.5);

      expect(p1.shouldRepaint(p2), isFalse);
      expect(p1.shouldRepaint(p3), isTrue);
      expect(p1.shouldRepaint(p4), isTrue);
      expect(p1.shouldRepaint(p5), isTrue);
      expect(p1.shouldRepaint(p6), isTrue);
    });

    testWidgets('paints fallback onto canvas without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 200,
                child: CustomPaint(
                  painter: CrtShaderOverlayPainter(
                    scanlineIntensity: 0.3,
                    vignetteIntensity: 0.4,
                    curvature: 0.05,
                    phosphorIntensity: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('CrtShaderOverlay owns a shader and unmounts without hanging', (tester) async {
      await CrtShaderLoader.initialize();
      expect(CrtShaderLoader.isReady, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 200,
                child: CrtShaderOverlay(
                  scanlineIntensity: 0.3,
                  vignetteIntensity: 0.4,
                  curvature: 0.05,
                  phosphorIntensity: 1.0,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CrtShaderOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(find.byType(CrtShaderOverlay), findsNothing);
    });
  });

  group('AgiPictureWidget CRT Shader Integration', () {
    testWidgets('renders CRT overlay when enableCrtShader is true', (tester) async {
      final visual = Uint8List(AgiDisplay.nativeWidth * AgiDisplay.pictureHeight);
      final pri = PriorityBuffer();
      final slices = PictureSlicer.slice(visualPixels: visual, priorityBuffer: pri);
      final pic = AgiPic(
        visualPixels: visual,
        priorityBuffer: pri,
        slices: slices,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgiPictureWidget(
              picture: pic,
              enableCrtShader: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(AgiPictureWidget), findsOneWidget);
      expect(find.byType(CrtShaderOverlay), findsOneWidget);
    });

    testWidgets('omits CRT overlay when enableCrtShader is false', (tester) async {
      final visual = Uint8List(AgiDisplay.nativeWidth * AgiDisplay.pictureHeight);
      final pri = PriorityBuffer();
      final slices = PictureSlicer.slice(visualPixels: visual, priorityBuffer: pri);
      final pic = AgiPic(
        visualPixels: visual,
        priorityBuffer: pri,
        slices: slices,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgiPictureWidget(
              picture: pic,
              enableCrtShader: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(CrtShaderOverlay), findsNothing);
    });
  });
}
