/// Immutable decoded snapshot of one OPL2 channel (copied values).
final class OplChannelSnapshot {
  final int channel;
  final int fnum;
  final int block;
  final bool keyOn;
  final int feedback;
  final int connection;
  final int modulatorOffset;
  final int carrierOffset;

  const OplChannelSnapshot({
    required this.channel,
    required this.fnum,
    required this.block,
    required this.keyOn,
    required this.feedback,
    required this.connection,
    required this.modulatorOffset,
    required this.carrierOffset,
  });
}

/// Immutable decoded snapshot of one OPL2 operator (copied values).
final class OplOperatorSnapshot {
  final int channel;
  final int operatorIndex;
  final int registerOffset;
  final double mult;
  final int ksr;
  final int ksl;
  final int tl;
  final int ar;
  final int dr;
  final int sl;
  final int rr;
  final bool am;
  final bool vib;
  final bool egType;
  final int waveform;
  final double envelopeDb;
  final int envelopeSegment;
  final int phase;

  const OplOperatorSnapshot({
    required this.channel,
    required this.operatorIndex,
    required this.registerOffset,
    required this.mult,
    required this.ksr,
    required this.ksl,
    required this.tl,
    required this.ar,
    required this.dr,
    required this.sl,
    required this.rr,
    required this.am,
    required this.vib,
    required this.egType,
    required this.waveform,
    required this.envelopeDb,
    required this.envelopeSegment,
    required this.phase,
  });
}

/// Immutable decoded snapshot of the whole chip (copied values).
final class OplDebugSnapshot {
  final int noteSel;
  final bool csm;
  final bool amDepth;
  final bool vibDepth;
  final int rhythmBits;
  final List<OplChannelSnapshot> channels;
  final List<OplOperatorSnapshot> operators;

  const OplDebugSnapshot({
    required this.noteSel,
    required this.csm,
    required this.amDepth,
    required this.vibDepth,
    required this.rhythmBits,
    required this.channels,
    required this.operators,
  });
}

/// One captured register write with the frame index at which it occurred.
final class OplWriteRecord {
  final int frameIndex;
  final int address;
  final int value;

  const OplWriteRecord({
    required this.frameIndex,
    required this.address,
    required this.value,
  });
}
