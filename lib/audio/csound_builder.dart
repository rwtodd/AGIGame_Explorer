import 'package:flutter_agigame/domain/sound.dart';

/// Builder for generating CSound score (.sco) and orchestra (.orc) files from [AgiSound] resources.
class CSoundBuilder {
  const CSoundBuilder._();

  /// Generates a CSound score (.sco) string from [sound].
  ///
  /// [soundNumber]: The resource number for commenting.
  static String buildScore({
    required AgiSound sound,
    int soundNumber = 0,
  }) {
    final buf = StringBuffer();
    buf.writeln(';; AGI Sound Resource $soundNumber\n');
    buf.writeln('t 0 3600 ;; AGI runs in 1/60th second ticks\n');
    buf.writeln('; set up the instruments if using a MIDI-converted orchestra');
    buf.writeln('i 1  0  0  1   0 4   ;; 4 Rhodes piano');
    buf.writeln('i 1  0  0  2   0 4   ;; 4 Rhodes piano');
    buf.writeln('i 1  0  0  3   0 4   ;; 4 Rhodes piano\n');
    buf.writeln('; set up the panning');
    buf.writeln('i 2  0  0  1 0.5     ;; middle');
    buf.writeln('i 2  0  0  2 0.7     ;; right');
    buf.writeln('i 2  0  0  3 0.3     ;; left\n');

    var curVoice = 10;
    if (sound.voices.isEmpty) {
      buf.writeln(';; No tonal voices for this sound. noise-only!\n');
    }

    for (final voice in sound.voices) {
      ++curVoice;
      buf.writeln(';; Start of voice ${curVoice - 10} (instrument $curVoice)');
      buf.writeln(';;\tstart\tdur\tlevel\tfreq');

      for (final note in voice.notes) {
        buf.writeln(
          'i$curVoice\t${note.startTime}\t${note.duration}\t${note.attenuation}\t${note.frequencyCount}',
        );
      }
      buf.writeln(';; End of instrument $curVoice\n');
    }

    if (sound.noise != null && sound.noise!.noises.isNotEmpty) {
      buf.writeln(';; Start of noise channel (instrument 21 and 31)');
      buf.writeln(';;\tstart\tdur\tlevel\tfreq');

      for (final noise in sound.noise!.noises) {
        final inst = (noise.type == NoiseType.white) ? 21 : 31;
        buf.writeln(
          'i$inst\t${noise.startTime}\t${noise.duration}\t${noise.attenuation}\t${noise.frequencyCount}',
        );
      }
      buf.writeln(';; End of noise channel\n');
    } else {
      buf.writeln(';; No noise channel in this sound.\n');
    }

    buf.writeln(';; mixer\n;;\tstart\tdur\trev\tlvl1\tlvl2');
    buf.writeln('i99\t0\t${sound.length + 60}\t0.9\t1.0\t1.0\n');

    return buf.toString();
  }

  /// Authentic Tandy 3-Voice CSound orchestra (.orc).
  static const String tandyOrchestra = '''
sr = 48000
ksmps = 32
nchnls = 1
0dbfs = 1

;; AGI sound-alike envelope
gienv	ftgen	0, 0, 4096, 7, 0.95, 8,  1, 9,  0.95, 9,  0.9, 8,   0.85, 43,  0.8, 51,  0.75, 85,  0.6, 444,  0.2, 409, 0.15, 1195,  0

;; noise wave...16 units long: 1 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0
ginzw	ftgen	0, 0, 16, -7, 1, 1, 1, 0, 0, 15, 0

gaOut	init	0.0

instr   1     ;; load program (no-op for this orchestra)
inoop = p4
inoop2 = p5
inoop3 = p6
endin

instr   2     ;; set panning (no-op for this orchestra)
iWhich  = p4
iPanVal = p5
endin

instr	11,12,13    ;; square waves
; i11	p2	p3	p4	p5
;	start	dur	ampl	pitch
iampl   =       ampdbfs(-20 - 3 * p4)
ifreq   =       111860.78125 / p5
kenv	oscili	1, 0.125, gienv
asq	vco2	iampl, ifreq, 2, 0.5
aenv	=	asq*kenv
gaOut	+=	aenv
endin

instr 21 ;; "white" noise
iampl	=	ampdbfs(-20 - (3*p4))
ifreq   =       111860.78125 / p5
idens = (ifreq/2) ;; impulses per sec
iperiod = (ifreq/16)
adust	dust	1, idens
aphase, aunused syncphasor iperiod, adust
aout table aphase, ginzw, 1
aout    *= iampl
gaOut	+= aout
endin

instr 31 ;; linear/periodic noise
iampl	=	ampdbfs(-20 - (3 * p4))
ifreq   =       111860.78125 / p5
iperiod = ifreq/16
aout oscil iampl, iperiod, ginzw, (1.001/16)
gaOut += aout
endin

instr	99 ;; out-mixer
kslope init p5
if p5 != p6 then
	kslope	expon	p5, p3, p6
endif
	out gaOut*kslope
gaOut	=	0
endin
''';

  /// Enhanced PWM CSound orchestra with stereo spatialization.
  static const String pwmOrchestra = '''
sr = 48000
ksmps = 32
nchnls = 2
0dbfs = 1

;; AGI sound-alike envelope
gienv	ftgen	0, 0, 4096, 7, 0.95, 8,  1, 9,  0.95, 9,  0.9, 8,   0.85, 43,  0.8, 51,  0.75, 85,  0.6, 444,  0.2, 409, 0.15, 1195,  0
ginzw	ftgen	0, 0, 16, -7, 1, 1, 1, 0, 0, 15, 0

gaLeft		init	0.0
gaRight 	init	0.0

giPan1		init	0.5
giPan2		init	0.7
giPan3		init	0.3

instr   1     ;; load program
inoop = p4
endin

instr   2     ;; set panning
iWhich  = p4
iPanVal = p5
if (iWhich == 1) igoto firstSq
if (iWhich == 2) igoto secondSq
if (iWhich == 3) igoto thirdSq
goto after

firstSq:
   giPan1 = iPanVal
   igoto after
secondSq:
   giPan2 = iPanVal
   igoto after
thirdSq:
   giPan3 = iPanVal
after:
endin

instr	11    ;; square wave 1
iampl	=	ampdbfs(-20 - (3*p4))
ifreq   =       111860.78125 / p5
kenv	oscili	1, 0.125, gienv
klfo	=	oscil:k(0.2,0.5,-1,random:i(0.75,1.0))+0.5
asq	vco2	iampl, ifreq, 2, klfo
aenv	=	asq*kenv
aoL, aoR pan2	aenv, giPan1, 0
gaLeft	+=	aoL
gaRight +=	aoR
endin

instr	12    ;; square wave 2
iampl	=	ampdbfs(-20 - (3*p4))
ifreq   =       111860.78125 / p5
kenv	oscili	1, 0.125, gienv
klfo	=	oscil:k(0.2,0.5,-1,random:i(0.75,1.0))+0.5
asq	vco2	iampl, ifreq, 2, klfo
aenv	=	asq*kenv
aoL, aoR pan2	aenv, giPan2, 0
gaLeft	+=	aoL
gaRight +=	aoR
endin

instr	13    ;; square wave 3
iampl	=	ampdbfs(-20 - (3*p4))
ifreq   =       111860.78125 / p5
kenv	oscili	1, 0.125, gienv
klfo	=	oscil:k(0.2,0.5,-1,random:i(0.75,1.0))+0.5
asq	vco2	iampl, ifreq, 2, klfo
aenv	=	asq*kenv
aoL, aoR pan2	aenv, giPan3, 0
gaLeft	+=	aoL
gaRight +=	aoR
endin

instr 21 ;; white noise
iampl	=	ampdbfs(-20 - (3*p4))
ifreq   =       111860.78125 / p5
idens = (ifreq/2)
iperiod = (ifreq/16)
adust	dust	1, idens
aphase, aunused syncphasor iperiod, adust
aout table aphase, ginzw, 1
aout *= iampl
gaLeft += aout
gaRight += aout
endin

instr 31 ;; linear noise
iampl	=	ampdbfs(-20 - (3 * p4))
ifreq   =       111860.78125 / p5
iperiod = ifreq/16
aout oscil iampl, iperiod, ginzw, (1.001/16)
gaLeft += aout
gaRight += aout
endin

instr	99 ;; out-mixer
aoL	reverb	gaLeft, p4
aoR	reverb	gaRight, p4
kslope init p5
if p5 != p6 then
	kslope	expon	p5, p3, p6
endif
	out (aoL*kslope), (aoR*kslope)
gaLeft	=	0
gaRight =	0
endin
''';
}
