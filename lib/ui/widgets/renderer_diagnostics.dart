import 'dart:ui';

import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Immutable snapshot of the playfield renderer's current layout and mode.
///
/// Published once per [GamePlayfieldWidget] layout pass and surfaced in the
/// debug inspectors (and their copied-state JSON) instead of an on-screen
/// badge overlay.
class RendererDiagnostics {
  final AgiPictureRenderMode renderMode;
  final bool shaderActive;
  final Size windowSize;
  final Size playfieldSize;
  final double devicePixelRatio;
  final int? picNumber;
  final bool strictIntegerScaling;
  final bool correctAspectRatio;

  const RendererDiagnostics({
    required this.renderMode,
    required this.shaderActive,
    required this.windowSize,
    required this.playfieldSize,
    required this.devicePixelRatio,
    required this.picNumber,
    required this.strictIntegerScaling,
    required this.correctAspectRatio,
  });

  double get scaleX => playfieldSize.width / 320.0;

  double get scaleY => playfieldSize.height / 200.0;

  Size get deviceWindowSize =>
      Size(windowSize.width * devicePixelRatio, windowSize.height * devicePixelRatio);

  Size get devicePlayfieldSize =>
      Size(playfieldSize.width * devicePixelRatio, playfieldSize.height * devicePixelRatio);

  /// The former on-playfield badge's 4-line text, verbatim.
  String describe() {
    return '${shaderActive ? 'PRIORITY SHADER' : 'PRIORITY SHADER: FALLBACK'}\n'
        'win ${windowSize.width.toStringAsFixed(1)}x${windowSize.height.toStringAsFixed(1)} dpr $devicePixelRatio '
        'dev ${(windowSize.width * devicePixelRatio).round()}x${(windowSize.height * devicePixelRatio).round()}\n'
        'pf ${playfieldSize.width.toStringAsFixed(1)}x${playfieldSize.height.toStringAsFixed(1)} '
        'dev ${(playfieldSize.width * devicePixelRatio).round()}x${(playfieldSize.height * devicePixelRatio).round()}\n'
        'scale ${scaleX.toStringAsFixed(4)} x ${scaleY.toStringAsFixed(4)} '
        'pic $picNumber int ${strictIntegerScaling ? "on" : "off"} 4:3 ${correctAspectRatio ? "on" : "off"}';
  }

  Map<String, dynamic> toJson() => {
        'renderMode': renderMode.name,
        'shaderActive': shaderActive,
        'windowSize': {'width': windowSize.width, 'height': windowSize.height},
        'playfieldSize': {'width': playfieldSize.width, 'height': playfieldSize.height},
        'devicePixelRatio': devicePixelRatio,
        'deviceWindowSize': {'width': deviceWindowSize.width, 'height': deviceWindowSize.height},
        'devicePlayfieldSize': {'width': devicePlayfieldSize.width, 'height': devicePlayfieldSize.height},
        'scaleX': scaleX,
        'scaleY': scaleY,
        'picNumber': picNumber,
        'strictIntegerScaling': strictIntegerScaling,
        'correctAspectRatio': correctAspectRatio,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RendererDiagnostics &&
          other.renderMode == renderMode &&
          other.shaderActive == shaderActive &&
          other.windowSize == windowSize &&
          other.playfieldSize == playfieldSize &&
          other.devicePixelRatio == devicePixelRatio &&
          other.picNumber == picNumber &&
          other.strictIntegerScaling == strictIntegerScaling &&
          other.correctAspectRatio == correctAspectRatio;

  @override
  int get hashCode => Object.hash(
        renderMode,
        shaderActive,
        windowSize,
        playfieldSize,
        devicePixelRatio,
        picNumber,
        strictIntegerScaling,
        correctAspectRatio,
      );
}

/// Returns [snapshot] with a top-level `renderer` key holding
/// [diagnostics], or [snapshot] itself when [diagnostics] is null.
///
/// Used only for copied/inspected JSON; save-file serialization never
/// passes through here.
Map<String, dynamic> injectRendererDiagnostics(
  Map<String, dynamic> snapshot,
  RendererDiagnostics? diagnostics,
) {
  if (diagnostics == null) return snapshot;
  return {...snapshot, 'renderer': diagnostics.toJson()};
}
