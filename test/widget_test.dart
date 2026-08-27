import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/main.dart';

void main() {
  testWidgets('Launcher screen renders title and directory card', (WidgetTester tester) async {
    // Set a large desktop size for tester
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: SierraAgiApp(),
      ),
    );

    // Verify header and UI components render
    expect(find.text('SIERRA AGI WORKBENCH'), findsOneWidget);
    expect(find.text('GAME DIRECTORY'), findsOneWidget);
    expect(find.text('Browse...'), findsOneWidget);
    expect(find.text('No Game Loaded'), findsOneWidget);
    final expectedBadge = Platform.isMacOS
        ? 'macOS Native'
        : Platform.isWindows
            ? 'Windows Native'
            : Platform.isLinux
                ? 'Linux Native'
                : 'Native';
    expect(find.text(expectedBadge), findsOneWidget);
  });
}
