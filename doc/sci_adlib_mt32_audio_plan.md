# SCI AdLib / Sound Blaster and future MT-32 audio plan

Status: **stages 0–4 landed 2026-11-26; stage 5 is next.**
Date: 2026-11-22.

Progress: stage 4 landed the pure Dart YM3812 (OPL2) core
(`lib/audio/opl/opl2_chip.dart`, snapshots in
`lib/audio/opl/opl_debug_snapshot.dart`): mono 49,716 Hz, integer 20-bit
phase, generated sine/amp tables, log-domain envelope with documented
rate-curve approximation, FM/additive, feedback, waveforms 0–3, AM/VIB,
write-log capture, and saturating mix. Tests in `test/audio/opl2_chip_test.dart`
(20 tests) pass; `dart analyze` clean; `test/audio/` (113) and `test/sci/`
(370) green. Perf (JIT debug, 9 channels keyed): 5 s render in ~90 ms
(debug budget <500 ms; release budget ~250 ms).
Stage 3 landed the patch-bank parser and loader
(`lib/audio/opl/sci_adlib_patch.dart`): 28-byte records with retained raw
bytes, 1344/2690 containers (second half at `2 + 28*i`, separator bytes
between halves — not a file prefix), inverted algorithm flag, embedded
`ADL.DRV` extractor with the exact {5684, 5720, 5727} size allowlist at
offset `0x45a`, and provenance-distinguished loading (volume / loose
patch / embedded `ADL.DRV` / unavailable). Corpus gates pass: PQ2 48
instruments, SQ3 96, KQ4 SCI 48 via embedded bank. The 5382-byte SCI1.1
form is rejected with a typed unsupported error, as documented.
Stage 0 inventory test covers all 10 local SCI titles (patch 3
at 1,344 or 2,690 bytes everywhere except KQ4's embedded-bank case).
Stage 1 landed the shared pull transport: `AgiPcmSource` is
byte-identical to the old offline renderer (golden hashes pinned from
pre-refactor output, block-size invariant), and `AgiSoundPlayer` is now a
facade over `StreamingPcmPlayer`. One old test assertion changed: queued
buffer count is now chunk-based rather than one whole-track write.
Stage 2 landed the lossless model: `SciMidiTrack`/`SciMidiParser` keep
the full header, event stream, cues, loop, and digital sample; the
legacy translation is now an adapter with note-for-note regression tests
(verified identical output on 9 synthetic streams × 3 modes before and
after the refactor).

Related existing design: [sound_system_design.md](sound_system_design.md),
[sci0_dual_engine_architecture.md](sci0_dual_engine_architecture.md), and
[review_followups.md](review_followups.md).

## Goal

Add authentic Sierra SCI AdLib / Sound Blaster FM output, first as a pure
Dart YM3812 (OPL2) device driven by the instrument data Sierra shipped with
each game. Reuse the resulting MIDI-event and PCM-source architecture for
AGI FM presets, Sound Blaster digital samples, and—later—Roland MT-32
without redesigning the sequencer again.

The first playable milestone is deliberately narrow: a selected SCI0 title
plays its AdLib soundtrack and sound effects through the existing macOS and
Windows PCM sinks, with correct cues, looping, pause/resume, and stop.
Everything after that is layered onto the same device-neutral event stream.

## Short answer: where Sierra stores the configuration

We are lucky. The core instrument configuration is **game resource data**,
not merely code hidden in a DOS driver:

- SCI patch resource **3** (`patch.003`) is the AdLib/Sound Blaster bank.
  It normally lives inside `RESOURCE.00x`; a loose `patch.003` file should
  override it through the existing loose-patch resource mechanism.
- The formats ScummVM accepts are:
  - 1,344 bytes: 48 instruments × 28 bytes.
  - 2,690 bytes: 48 instruments, a two-byte separator between the halves,
    then 48 more (second half at `2 + 28*i`; the separator bytes are never
    record data).
  - 5,382 bytes: the later SCI1.1 form, 190 instruments plus a rhythm map.
    It is outside the SCI0 first slice, but the parser should reject it
    deliberately rather than misread it.
- Early SCI0 games without patch resource 3 can carry a 1,344-byte bank
  inside `ADL.DRV`. ScummVM recognizes only driver sizes 5684, 5720, and
  5727 and reads that bank at offset `0x45a`. King's Quest IV SCI is the
  local case: it has no patch 3 resource and its `ADL.DRV` is 5,720 bytes.
- The executable drivers also contain device logic—voice assignment,
  velocity and pan translation, note stealing, init-track behavior, and
  hardware programming—so the project still needs its own Sierra-compatible
  software driver layer above the chip.
- `ADL.DRV` and `SNDBLAST.DRV` do not imply different patch banks. In
  Space Quest III they are byte-identical; in other games the builds differ,
  but they consume the same patch resource 3. Sound Blaster's distinct
  feature is its digital sample channel, not a different SCI instrument bank.
- Patch resource 1 is the MT-32 data for the later stage. Patch 0 is a
  separate D-110 format and must not be confused with it.
- `RESOURCE.CFG` merely names the selected Sierra driver, for example
  `soundDrv=ADL.DRV`; it does not contain FM instrument definitions.

The current local corpus survey found patch 3 at 1,344 bytes in Police
Quest 2 and Leisure Suit Larry 2, and at 2,690 bytes in Space Quest 3,
Leisure Suit Larry 3, Codename: Iceman, The Colonel's Bequest, Conquests
of Camelot, and Quest for Glory I. Quest for Glory II needs a follow-up
inventory because the probe hit an existing decompression limitation.

## Decisions already made

1. **Pure Dart first.** Implement a clean-room, register-level YM3812 core
   and Sierra AdLib driver in Dart. This preserves hot reload, direct state
   introspection for debugging, a single cross-platform code path, and no
   new native build or licensing dependency.
2. **Target OPL2 before marketing it as OPL3.** Original AdLib and the
   first Sound Blaster are one YM3812. YMF262/OPL3 is register-compatible
   and may become an extension, but SCI0 Sierra data and drivers exercise
   the nine-voice, two-operator OPL2 device. Calling the first version a
   complete OPL3 emulator would overclaim it.
3. **Mono first, stereo deliberately second.** A single OPL2 is mono.
   ScummVM optionally runs a dual-OPL2 pair to implement MIDI pan. We will
   prove the mono register core first, then decide between post-pan,
   dual-chip pan, or OPL3-style channel selections using listening tests.
4. **Preserve SCI events; do not keep flattening them into AGI notes.** A
   new device-neutral SCI MIDI event/track model is the foundation. The
   existing Tandy/PC-speaker translation becomes one adapter over it rather
   than remaining the only parsed representation.
5. **Keep the existing PCM sinks and unify playback on pull-based sources.**
   `AudioOutputSink` already provides the correct platform boundary. Before
   connecting OPL, extract one streaming player and convert the existing AGI
   renderer into its first production `PcmSource`. AGI, legacy SCI, OPL, and
   later MT-32/sample sources then share transport, position, pause, seek,
   loop, completion, and underrun handling rather than growing separate
   players. Offline `renderPcm` remains a facade over the same source for
   WAV export and deterministic tests.
6. **Do not transliterate ScummVM code.** ScummVM and DOSBox code are
   behavioral references. Sierra formats, the Yamaha datasheet, and
   observed game data define the implementation. This matters because the
   repository currently has no project license, while ScummVM's driver is
   GPL-licensed. Nuked OPL3 may be used as a development oracle, not vendored
   without a separate licensing and packaging decision.
7. **MT-32 stays a later backend, not another sequencer.** The event model
   must preserve SysEx and all controller/program data from the beginning so
   a future Munt or external-MIDI backend can consume the same stream.

## Scope and non-goals

### In scope for the first feature train

- A shared pull-based PCM transport, with the existing AGI renderer converted
  to it before SCI OPL integration and its offline render API preserved.
- SCI0-early and SCI0-late sound-resource headers, device masks, control
  channel, cues, and loop points.
- `patch.003`, including loose-file override and the supported early
  `ADL.DRV` embedded-bank fallback.
- A register-level YM3812 core, Sierra voice allocation, note/volume/pan/
  pitch-bend/hold behavior, and PCM streaming into the current sinks.
- SCI0 digital-sample playback as a distinct stage after FM music works.
- AGI playback through FM instrument presets, with optional SN76489 noise.
- User-visible device selection, presets, diagnostic state, and safe fallback
  to the current renderer when a required bank is unavailable.
- A Sound Browser path for auditioning SCI sounds and exporting WAV renders.

### Out of scope until separately planned

- MT-32 or Munt integration and any distribution of Roland ROM images.
- General MIDI, SoundFonts, CMS/Game Blaster, FB-01, Casio, Amiga, FM Towns,
  or PC-98 devices.
- Full OPL3 four-operator and 18-channel behavior.
- SCI1/SCI1.1 multi-track selection beyond making their data structures not
  poison the SCI0 design.
- Replacing the AGI parser or current SN76489 synthesis path.
- Removing the legacy Tandy/PC-speaker SCI translations. They remain useful
  fallbacks and regression oracles throughout migration.

## Current-state findings

- `Sci0SoundParser.parseSound` immediately translates SCI MIDI into the AGI
  `AgiSound` model. In doing so it drops program changes outside channel 15,
  controllers, pitch bend, aftertouch, SysEx, polyphony, per-note identity
  within a channel, most header voice data, and the digital sample payload.
- SCI therefore offers no distinct instrument layer today: `SciKernel`
  parses with one of the existing PC-speaker/Tandy/enhanced modes and hands an
  `AgiSound` to the same `AgiSoundPlayer` used by AGI.
- `AgiSoundPlayer` pre-renders an entire `AgiSound` before playback and
  uses a stopwatch for position. That is acceptable for current finite AGI
  sounds, but it is the wrong long-term shape for a stateful FM chip, live
  controls, long SCI tracks, and register debugging.
- SCI's cue clock is independently advanced by the engine. The new design
  must define whether the sequencer's generated-frame position or engine
  tick clock is authoritative; the plan below makes frame position the
  sequencer's source of cue-release truth and adds drift tests.
- `SciSoundHardwareMask.adLib` exists, but the parser never selects the
  AdLib channels. The early/late SCI0 header rules need to be modeled
  precisely rather than inferred from byte 0.
- The current SCI sound header comments conflate the digital-sample flag
  with a track count. Per ScummVM and the SCI specification, SCI0 has one
  event stream; byte 0 says whether a digital sample follows, then each of
  16 logical channels has either one initialization byte (early) or a
  voice-count/play-mask pair (late).
- The existing debug inspector has no SCI audio tab, and the existing Sound
  Browser is AGI-only.

## Source-data model

### SCI0 sound resource

The event parser will retain, at minimum:

- format variant: early 17-byte header or late 33-byte header;
- the raw 16 channel initialization records;
- per-channel requested hardware-voice count and device play mask;
- the complete timed event stream, including running status expansion;
- note on/off, program change, controllers, pitch bend, channel pressure,
  polyphonic pressure where present, SysEx, Sierra cue/loop messages, and
  end-of-track;
- the optional unsigned 8-bit digital sample, its 44-byte header fields,
  sample rate, bounds, and payload offset;
- total duration and precomputed cue/loop points for the script engine.

The legacy conversion to `AgiSound` becomes a device adapter over this
model. It must produce byte-for-byte or note-for-note equivalent current
output for existing tests until intentionally replaced.

### SCI channel selection

The header is device data, not a hint to approximate:

- Early: one byte per channel. Upper nibble is requested voices; lower
  bits identify device classes; bit 3 participates in identifying the
  control/rhythm interpretation. AdLib ignores a channel with bit 3 set.
- Late: voice-count byte plus play-mask byte. AdLib's late play flag is
  `0x04`; early's effective AdLib bit is `0x01` in the low device bits.
- Channel 15 is always retained for cues/control even when it produces no
  audible notes.
- Channel 9 does not become hardware rhythm mode in SCI0. It remains data
  for ordinary driver interpretation unless a device profile says otherwise.

### Patch resource 3

Each instrument record is 28 bytes: two 13-byte operator descriptions plus
waveform bytes. The parser will expose both:

- the original record bytes, for exact debug display and golden tests; and
- decoded operator/modulator fields, for formatting registers.

The loader order will be:

1. Effective volume-manager resource `SciResourceType.patch`, number 3,
   including a loose `patch.003` override.
2. For a small allowlist of exactly recognized early `ADL.DRV` sizes,
   1,344 bytes at offset `0x45a`.
3. No synthetic silent bank substitution. Report the bank as unavailable and
   let device selection fall back under the user-visible policy below.

Loose-patch header stripping in the existing volume manager must be
exercised explicitly: a loose patch file and the same bank packed in a
volume should decode to the same instruments.

### SCI digital samples

A sample is not part of the FM patch or OPL register state. It is an
unsigned 8-bit PCM payload with a 44-byte header; rate and length are read
from offsets 14 and 32 in that sample header. It gets its own PCM source and
mixer input in stage 8. Calling that stage "Sound Blaster completion" is
more accurate than treating sample playback as part of the OPL chip.

## Target architecture

```text
AGI SOUND data ──> AgiPcmSource (SN76489 / enhanced) ───────────────┐
AGI SOUND data ──> AgiFmAdapter ──> SierraMidiDevice ──> PCM source ─┤
SCI SOUND bytes ─> SciMidiTrack ─> Sequencer ─> MidiDevice ─> PCM ──┤
SCI digital data ─────────────────> sample PCM source ───────────────┤
                                                                     v
                                              optional mixer PcmSource
                                                                     │
                                                                     v
                                                        StreamingPcmPlayer
                                                                     │
                                                                     v
                                                           AudioOutputSink
```

`SierraMidiDevice` implementations are the Sierra AdLib driver over the
YM3812 chip, the legacy SCI PSG adapter during migration, and MT-32 later.
The native AGI source bypasses the MIDI-device layer; only the optional AGI
FM enhancement uses that layer.


### Event and device interfaces

Design the default interfaces around sample positions, not wall-clock time:

- `SciMidiTrack` is immutable after parsing and contains ticks at 60 Hz.
- `SciMidiSequencer` owns one active SCI sound, emits events due within a
  requested frame interval, exposes cue events stamped by generated frame,
  and knows the loop point.
- `SierraMidiDevice` accepts track initialization, short MIDI messages,
  complete SysEx payloads, reset/all-notes-off, master volume, and a
  capability report. It renders only through a `PcmSource` so Munt can later
  implement the same sequencer-facing contract.
- `PcmSource.renderInto(Int16List interleaved, int frameCount)` is
  deterministic, non-allocating in steady state, and independent of Flutter
  widgets. A player-level fill loop maintains a bounded lookahead in the
  existing sink ring buffers and uses sink `playedFrames` as the audible
  clock for cue delivery where available.
- The script-facing SCI slot must no longer tell `AgiSoundPlayer` to play a
  pre-translated `AgiSound` when a MIDI device is selected. It starts,
  pauses, stops, fades, and polls the sequencer instead.
- Legacy SCI PSG translation remains a device implementation during
  migration. Device switching stops active notes, resets the old device, and
  restarts at a sequencer position only where existing SCI semantics say a
  mode change restarts parsing; otherwise it takes effect on the next sound.

### Pure Dart YM3812 core

The chip API intentionally resembles hardware rather than a note synthesizer:

- `reset()`;
- `writeRegister(int address, int value)` for the 256-byte OPL2 map;
- `generate(Int16List output, int frameCount)` at the chip's native
  49,716 Hz-derived internal rate;
- `snapshot()` returning decoded register/operator/voice state for debug;
- optional write-log capture used only when diagnostics are enabled.

The first core implements the data-sheet feature set Sierra exercises:
nine 2-operator melodic channels; phase and envelope generators; key scale
rate/level; attack/decay/sustain/release; feedback; FM and additive
connection; selectable waveforms; tremolo and vibrato; key-on/off;
frequency number/block; and output mixing/clipping. Rhythm mode, timers,
IRQ/status behavior, composite sine mode, and deep hardware test registers
are explicitly staged later unless a game fixture proves one is audible.

Generated samples are resampled from 49,716 Hz to the sink rate in a
separate reusable component. The initial resampler may be linear for the
first audible milestone only if labelled as such in benchmarks; the release
gate requires a measured choice between linear and polyphase/windowed-sinc
quality and CPU. Do not hide resampling by simply running the chip at
44,100 Hz: that changes pitch and envelope timing unless every divider is
modeled relative to output rate and separately validated.

The OPL stereo stage may instantiate two chip cores to emulate ScummVM's
dual-OPL2 pan behavior. The initial release can be mono duplicated to both
sink channels, which is authentic to the original AdLib/Sound Blaster
baseline. A single-chip post-pan approximation must be identified as an
enhancement rather than silently conflated with dual-chip behavior.

### Sierra AdLib software driver

Above the chip, a Sierra-specific driver owns:

- patch bank selection and the default patch used before program changes;
- SCI track-header voice assignment (`initTrack` semantics);
- 16 logical MIDI channels mapped to at most nine physical voices (eight
  for the early driver profile where required);
- oldest-voice stealing, retrigger, sustain-pedal behavior, all-notes-off;
- program change, channel volume, pan, pitch bend, velocity enable, and
  dynamic voice-count controller `0x4B`;
- note range clipping and the Sierra frequency table / pitch-bend curve;
- SCI0 master volume scaling (0–15) separately from the OS/player volume.

Its register writes are the testable contract. Driver tests should be able
to run against a fake register sink without generating audio.

### Playback, mixing, and time

Convert AGI to the shared transport before SCI integration, rather than
adding a second SCI-only player and unifying them later:

- Extract the state in `PcmSynthesizer` into a resettable `AgiPcmSource`
  that renders requested frame ranges on demand. Its cursor must derive note
  boundaries from absolute sound ticks, not accumulated block-local time, so
  output does not drift with block size.
- Preserve `PcmSynthesizer.renderPcm` and `renderWav` as offline facades
  that repeatedly pull a fresh `AgiPcmSource`. Sound Browser export and
  existing tests therefore keep their meanings.
- Turn `AgiSoundPlayer` into a compatibility facade over
  `StreamingPcmPlayer`, retaining its constructor, position stream, status,
  volume, looping, seek, and completion callback for current engines and UI.
- The shared player owns one active source, or a mixer source when stages
  8–9 need simultaneous inputs. It maintains roughly 100–250 ms of queued PCM,
  refills from a timer while playing, and generates silence on underrun
  while counting underruns for diagnostics.
- Make the sink contract explicit that `writePcm` copies or consumes the
  supplied samples synchronously; update `NullAudioSink` to do the same.
  That allows the streaming player to reuse one interleaved block buffer.
- Position is defined in generated frames adjusted by audible sink progress
  where available. `playedFrames`, submitted frames, and queued frames must
  not be conflated in tests for pause, seek, loop, or completion.
- Sequencer events carry sample offsets within each generated block;
  applying all events only at block starts is acceptable for the first
  milestone if block size is no more than 512 output frames, and must be
  tightened if timing tests or listening reveal flam/zipper artifacts.
- Pause stops generation and holds synthesizer state; stop sends
  all-notes-off where applicable, resets the source, and flushes PCM so
  releases do not leak into the next sound.
- A mixer combines FM, optional retained Tandy noise, SCI digital samples,
  and later MT-32 PCM with explicit per-bus gains and soft clipping only at
  the final stage. Existing reverb remains an opt-in post effect, never a
  substitute for device output.

### Settings model

Avoid overloading the existing enum until its callers can move together:

- Add a distinct SCI music-device preference rather than pretending
  `PcmPlaybackMode` is a device. Proposed values are `auto`, `legacyPsg`,
  `adLibOpl2`, `soundBlasterOpl2Samples`, and disabled-until-implemented
  `mt32`. `AgiSoundMode` remains the AGI-native selector during migration.
- Add nested settings for AGI FM enablement, preset id, noise source, FM and
  noise gains, stereo width, and per-voice relative gains/pans. Persist them
  additively; old settings files load with today's audible defaults.
- Add OPL settings for master gain, mono/dual-chip stereo mode, output
  resampler quality if exposed, and digital-sample enablement/gain.
- A game-level override is desirable eventually because Sierra games ship a
  `RESOURCE.CFG`, but do not read or execute any part of that file beyond a
  strict allowlist parser for `soundDrv=` when the `auto` stage arrives.
- When patch 3/embedded bank is unavailable, show the reason in the audio
  UI and fall back only according to an explicit setting: `legacy` for the
  first release. Never silently substitute baked-in Sierra instrument bytes
  copied from a game or another emulator.

### AGI through the FM device

AGI gets an adapter, not a fake history lesson:

- Translate each `AgiNote` segment into note, frequency, velocity, and
  duration events at 60 Hz. Consecutive same-pitch attenuation changes update
  the active voice level without retriggering its envelope.
- Give the three AGI tone channels stable FM voices/channels. Do not force
  them through SCI patch numbers; use project-authored instruments encoded
  in the same decoded operator model as Sierra's 28-byte records.
- Ship a handful of named presets, each defining patches for lead, harmony,
  bass, and effects plus gains/pans. The first set should include a neutral
  FM keys/organ preset, a bright brass/lead preset, a soft organ preset, a
  bass-and-lead split, and a close-to-square preset for comparison.
- Keep the SN76489 noise generator as a separate mixed source by default.
  That preserves periodic and white AGI noise exactly. OPL rhythm/noise is
  an alternative preset color later; it cannot reproduce every SN76489 clock
  rate and feedback pattern through the normal melodic operators.
- AGI's `sound` browser and export path should preview the same renderer
  that gameplay uses, including WAV export. CSound and standard MIDI export
  retain their existing meanings.

### Debug and workbench experience

The existing modal SCI inspector pauses the engine, so it is suitable for a
frozen snapshot but not the only place for live tweaks. Split the work:

- **Sidebar Audio tab:** device/preset selection, master/FM/noise/digital
  gains, stereo width, per-AGI-voice pan and level, test chord, and fallback
  status. Changes take effect without restarting the track where the device
  contract permits.
- **SCI inspector Audio tab:** patch-bank provenance, sequencer position,
  active sound/cue queue, logical-channel state, and a snapshot of physical
  voices. It must copy state at a throttled rate; it must never read mutable
  chip internals from a build method.
- **Register view:** decoded global registers and, per physical channel,
  frequency/block/key-on and both operators' ADSR, multiplier, total level,
  waveform, AM/vibrato/envelope-type, scaling, feedback, and algorithm.
- **Patch view:** all loaded 28-byte records decoded by field, with raw hex
  available and the currently selected patch per logical channel.
- **Event/write trace:** optional bounded ring buffer of recent MIDI events
  and register writes. It is disabled by default and excluded from savegames.

### Keeping MT-32 unboxed-in

The future MT-32 driver is another `SierraMidiDevice`, not a second sound
parser:

- It receives the same note/controller stream and complete SysEx payloads.
- A patch-1 module translates Sierra's MT-32 patch resource into the SysEx
  initialization sequence and stores reverb/LCD data for the backend.
- The native Munt path remains a separate later decision. Munt provides a
  C-compatible wrapper, but it still introduces native build, distribution,
  and LGPL obligations; Roland ROMs are user supplied and never bundled.
- External OS MIDI output can share the message interface later, provided
  its clock/queue contract is kept outside the SCI sequencer.
- No OPL-specific type may leak into `SciMidiTrack`, `SciMidiSequencer`, or
  their cue API.

## Stepwise implementation

### Stage 0 — Resource and behavior inventory (no audible change)

- Add a small, checked-in inventory test or dev tool output for every local
  reference SCI title: patch resource sizes, patch 3 presence, sound count,
  early/late header classification, digital-sample count, program numbers,
  loop/cue counts, and `ADL.DRV` size. Reference game data remains outside
  git; tests skip absent titles.
- Resolve the Quest for Glory II inventory failure seen during planning
  separately or explicitly classify QFG2 as out of this feature's first
  acceptance set. Do not let it silently claim support.
- Capture manual ScummVM listening notes for PQ2 title/first rooms, one
  early KQ4 track, and one 96-instrument late-SCI0 track. Record device,
  sound number, timestamp, and distinctive instruments/drums, not ripped
  copyrighted audio in the repository.
- Decide and document the clean-room source policy for the chip: Yamaha
  register documentation and observed game data may define behavior;
  ScummVM identifies Sierra driver semantics and serves as a listening
  oracle, but its GPL implementation is not copied or transliterated.

**Exit gate:** the inventory runs against the local corpus and explains
every unavailable bank before synthesis work begins.

### Stage 1 — Shared pull-based PCM transport; convert AGI first

This stage intentionally precedes all OPL work. It proves the eventual
SCI playback path against the already-working AGI renderer and leaves one
player implementation for every later synthesis backend.

- Define `PcmSource` around reset/seek, generated-frame position, total
  frames where finite, finished state, and `renderInto` for an interleaved
  destination block. The contract must state whether rendering may return a
  short block only at end-of-stream.
- Extract a resettable, stateful `AgiPcmSource` from `PcmSynthesizer`.
  Preserve per-voice phase, note envelopes, the SN76489 LFSR and fractional
  shift-clock state, reverb filters, pan, limiter behavior, and the current
  50 ms / one-second tail rules across block boundaries.
- Keep `PcmSynthesizer.renderPcm` and `renderWav` as offline facades that
  drain a fresh `AgiPcmSource`; their public output must not change.
- Add `StreamingPcmPlayer` over the existing sinks. It owns one reusable
  interleaved block buffer, a bounded lookahead, underrun counting, and
  generated/audible frame accounting. Make synchronous copy semantics part
  of the `AudioOutputSink.writePcm` contract and update `NullAudioSink` to
  copy, matching the native ring-buffer sinks.
- Reimplement `AgiSoundPlayer` as a compatibility facade over the shared
  player, preserving its constructor, status and position streams, volume,
  mute, looping, `seekToTick`, and `onFinished` behavior for AGI and legacy
  SCI callers. No SCI OPL code is connected yet.
- Keep seek semantics simple at first: reset the source and generate/discard
  frames to the requested tick. Optimized random-access cursors are only
  justified if profiling shows the Sound Browser needs them.

**Exit gate:** for PC speaker, Tandy, and enhanced modes, pulling an AGI
sound in block sizes 1, 17, 512, and 4096 frames produces byte-identical
PCM to each other and to the pre-refactor `renderPcm` output, including
noise and reverb tails. Existing AGI player, Sound Browser, and SCI legacy
sound tests pass through the shared transport without timing regressions.

### Stage 2 — Lossless SCI MIDI event model

- Parse SCI0 into `SciMidiTrack` without discarding SysEx, program changes,
  controllers, pressure, or polyphony. Preserve running-status expansion,
  240-tick delta extensions, cues, and explicit loop position.
- Model header records and digital-sample presence; distinguish the stream
  payload from the sample payload instead of scanning into it as MIDI.
- Implement the legacy `AgiSound` conversion as an adapter over the new
  model. Freeze its output with note-for-note regression tests first.
- Calculate device channel-filter masks for AdLib, Tandy/PCjr, PC speaker,
  and future MT-32 from one shared header interpretation.
- Add a text/debug dump format for a parsed track. This becomes the fixture
  for driver tests that should not require copyrighted resources.

**Exit gate:** existing SCI sound tests stay green; synthetic streams prove
program/controller/pitch/SysEx/polyphonic events survive parsing and legacy
translation remains unchanged.

### Stage 3 — Patch-bank loader

- Decode 28-byte Sierra AdLib instruments and both accepted SCI0 container
  sizes. Reject unsupported sizes and truncated records with typed errors.
- Load through `SciVolumeManager.getResource(SciResourceType.patch, 3)`.
- Add the recognized early `ADL.DRV` embedded-bank extractor with an exact
  size/offset allowlist and filename matching that is case-insensitive.
- Expose provenance (`volume`, `loose patch`, `embedded ADL.DRV`, or
  unavailable) and the raw/decoded records for tests and debug UI.
- Build synthetic 1,344- and 2,690-byte banks byte-by-byte in tests; assert
  every field, including the inverted algorithm flag and waveform bytes.

**Exit gate:** PQ2's 48-instrument and SQ3's 96-instrument banks decode;
KQ4's embedded bank decodes; no Sierra patch bytes are checked into git.

### Stage 4 — Pure Dart YM3812 core (mono)

- Implement the register file and sample generation in fixed-size typed
  arrays with no steady-state allocation in `generate`.
- Add register-write tests before audible integration: key on/off, F-number
  and block tuning zero crossings, envelope segment ordering and release,
  waveform selection, feedback/algorithm differences, total-level scaling,
  pitch LFO/AM switches, and reset determinism.
- Benchmark in a release-mode harness. Initial budget: native-rate stereo
  generation should consume less than 5% of one modern desktop core and no
  more than 10% in a debug build; tighten after measuring. If Dart misses
  the budget, stop and revisit the FFI decision rather than optimizing by
  removing chip behavior silently.
- Compare a small set of synthetic register sequences against recorded
  ScummVM/DOSBox listening references and, if locally available, an
  out-of-tree Nuked oracle. Tolerances must be documented; initial success
  is musical/register fidelity, not claimed bit identity.

**Exit gate:** deterministic silent, single-note, envelope, and two-operator
fixtures pass, and a five-second render has bounded CPU with no clipping
unless the register program itself drives the core into clipping.

### Stage 5 — Sierra AdLib driver and offline audition

- Implement logical-channel state, track initialization, header voice
  assignment, note allocation/stealing, patch changes, controllers, pitch
  bend, hold, and all-notes-off against a fake register sink first.
- Encode early- versus late-SCI0 behavior explicitly; do not blur the
  driver profiles into a generic modern MIDI allocator.
- Add an offline render entry point used by tests and the future sound
  browser before wiring it into gameplay. This produces WAV-comparable PCM
  from a resource number without depending on speakers or wall time.
- Use register-write goldens for representative synthetic tracks. Register
  sequences are more stable than early chip PCM and isolate driver bugs
  from synthesis bugs.

**Exit gate:** PQ2 and KQ4 representative tracks produce non-silent,
finite PCM at expected duration; a listening comparison identifies no
missing instrument families; early-bank fallback works for KQ4.

### Stage 6 — Streaming playback and SCI integration

- Connect one SCI sound slot to the shared streaming player proven in
  stage 1, retaining the legacy translation for all non-AdLib modes.
- Preserve script-visible start, loop, pause, stop, dispose, master volume,
  fade-as-stop (or better if separately specified), and cue semantics.
  Every semantic difference from the legacy path needs a test named for it.
- Add the SCI device setting but leave the legacy PSG device as default
  during this stage. Include an immediate, audible fallback reason if the
  bank cannot load.
- Test back-to-back sounds, restarting a room, restoring a save while music
  is active, mute toggling, device switching, pause/resume, and a missing
  patch bank. No stuck key-on state may survive any transition.

**Exit gate:** PQ2 title and first-room sounds are playable end-to-end with
AdLib selected, cues still advance scripts, and switching back to Tandy has
no stuck notes or leaked timers.

### Stage 7 — Debug surface and basic live controls

- Add the sidebar controls and SCI inspector Audio tab described above.
- Make snapshot capture explicit and throttled; register writes from the UI
  are not part of this stage. Only driver-level gain, pan, mute/solo,
  stereo width, and patch override controls are writable.
- Persist only user preferences, never live chip registers or trace data.
- Add a one-click synthetic test chord and patch audition that do not
  require a game resource.

**Exit gate:** during a playing track, a reader can identify the bank
source, selected patch, physical voice/note, and decoded operator values;
changing channel gain/pan is audible on the next relevant note without
restarting the game.

### Stage 8 — Sound Blaster completion (stereo and digital samples)

- Parse and play the SCI0 unsigned 8-bit sample channel through the mixer,
  honoring when Sierra chooses it instead of, or alongside, the MIDI data.
- Decide from measurements and listening whether stereo is a post-panned
  mono core or two OPL2 cores with independent operator total levels, as in
  ScummVM's dual-OPL2 model. Label the UI accordingly; do not call a
  post-pan an OPL3 implementation.
- Only after those semantics are separated should an OPL3 bank-select /
  four-operator extension be considered. It is not needed to claim SCI0
  Sound Blaster support.

**Exit gate:** a known SCI0 digital-sample sound (including SQ3's sample
case) is audible at the recorded rate, FM-only sounds are unchanged, and a
stereo A/B check documents which model shipped.

### Stage 9 — AGI FM presets and noise

- Adapt AGI sounds into the same note-event interface without modifying the
  AGI parser's saved representation.
- Author a small preset bank in code and expose preset, per-voice gain/pan,
  FM gain, noise gain, and noise source in the sidebar and Sound Browser.
- Keep the existing Tandy noise mixed in by default. Sound effects that use
  the noise channel as pitched material need listening fixtures, because an
  FM-only mapping can lose their identity.
- Make game start/stop/flag behavior identical to today's AGI sound path;
  only timbre changes.

**Exit gate:** an AGI title fanfare, a noise-heavy effect, and a three-voice
music track retain timing, relative dynamics, and completion flags in both
Tandy and FM modes.

### Stage 10 — Default change and MT-32 readiness

- After a soak across the local SCI0 corpus, decide whether AdLib becomes
  the default for SCI or remains opt-in. Do not make that decision inside a
  synthesis bug fix.
- Freeze the `SierraMidiDevice` contract, then write the separate MT-32
  implementation plan covering patch 1 SysEx translation, ROM discovery and
  validation, Munt build/distribution, LCD/reverb behavior, and external
  MIDI as an alternative.
- Remove no legacy code until the selected default has survived at least
  one full play session in each of an early and a late SCI0 title.

## Proposed file map

Exact names can move during implementation, but responsibilities should not
be merged merely to save files:

- `lib/sci/engine/sci_midi_track.dart` — immutable header/event/sample model.
- `lib/sci/engine/sci_midi_parser.dart` — SCI0 decoding and channel masks.
- `lib/sci/engine/sci_midi_sequencer.dart` — frame-stamped event/cue delivery.
- `lib/audio/midi/sierra_midi_device.dart` — backend-neutral device contract.
- `lib/audio/opl/opl2_chip.dart` — register machine and sample generation.
- `lib/audio/opl/sci_adlib_patch.dart` — 28-byte record and bank parsing.
- `lib/audio/opl/sci_adlib_driver.dart` — Sierra channel/voice behavior.
- `lib/audio/opl/opl_debug_snapshot.dart` — immutable UI/test snapshots.
- `lib/audio/pcm_source.dart` — pull-render and resampling contracts.
- `lib/audio/agi_pcm_source.dart` — stateful SN76489/enhanced block renderer.
- `lib/audio/streaming_pcm_player.dart` — lookahead fill into current sinks.
- `lib/audio/agi_fm_adapter.dart` — AGI notes/noise to FM events and presets.
- `test/sci/sci_midi_parser_test.dart`, `test/audio/opl2_chip_test.dart`,
  `test/audio/sci_adlib_driver_test.dart`, and additions to existing SCI
  sound/settings/browser suites.

## Validation plan

### Automated checks per stage

- Parser: synthetic early/late headers; device masks; running status; SysEx
  preservation; program/controller/pitch events; loop points; truncated
  events; digital-sample separation; exact legacy-note regression output.
- Bank: all supported sizes, every decoded field, loose versus packed
  equivalence, unsupported embedded-driver sizes, and missing-bank errors.
- Chip: deterministic reset, silence without key-on, known sine periods,
  envelope ordering, operator routing, feedback stability, waveform
  selection, pitch/vibrato/tremolo switches, and bounded output.
- Driver: register-write sequences captured from a fake sink for track
  initialization, program changes, allocation/stealing, sustain, volume,
  pan, pitch bend, all-notes-off, and early/late profile differences.
- Player: event sample offsets, loop wraparound, pause/resume, underrun
  counting, device switching, and no leaked timers or key-on voices.
- Settings: additive JSON migration from a current settings fixture and
  preservation of every pre-existing field/value.

### Repository test commands

- Stage-local work: the new parser/chip/driver test files plus
  `test/sci/sci_sound_test.dart` and `test/audio/`.
- SCI integration gates: `flutter test test/sci/`.
- Shared session/settings/player changes: `flutter test` for the existing
  AGI tree as required by `AGENTS.md`, plus `flutter test test/sci/`.
- Every gate: `dart analyze`. On this machine run Flutter/Dart with the
  sandbox bypass required by `AGENTS.md` on the first attempt.

### Listening and performance checks

Automation cannot approve timbre. Each audible milestone needs a short,
dated listening record naming game, sound number or scene, device choice,
build type (debug/profile), sample rate, and what was compared:

1. PQ2 title and an early room sting.
2. KQ4 early title/room using the embedded bank.
3. One 96-instrument late-SCI0 title such as SQ3.
4. One SCI digital-sample effect after stage 8.
5. One AGI fanfare and one noise-driven AGI effect after stage 9.

Compare with the installed ScummVM 2.6.1 and, where practical, DOSBox-X.
They are listening oracles only; do not add their output or game patch bytes
as golden files to git. For synthetic sequences, PCM hashes and RMS/peak
checks are appropriate once our own renderer is intentionally frozen.

Performance gates should report Dart generation time for ten seconds of
audio, allocations after warm-up, underruns at the chosen lookahead, and
end-to-end CPU in a profile build. The relevant comparison is current
legacy SCI playback in the same scenes, not the chip core in isolation.

## Risks and unresolved questions

- **Accuracy ceiling of a clean-room core.** The public register map does
  not fully specify Yamaha's internal log/exp tables, envelope increments,
  output filtering, and every timing quirk. The plan accepts musical and
  register-level fidelity, not an initial bit-exactness claim. If users
  require bit-level output, stop and reassess FFI rather than accreting
  undocumented approximations.
- **Licensing discipline.** The project root currently has no license file.
  That makes "just borrow an emulator core" a distribution decision, not a
  mere dependency choice. ScummVM identifications and observed behavior can
  guide requirements; its GPL source should not be copied or transliterated
  into the Dart chip/driver.
- **SCI0 caps/header semantics.** ScummVM's own `initTrack` handling of the
  first header byte is not fully explanatory. Stage 2 must validate against
  all local titles before freezing the early/late classification API.
- **Unsupported embedded banks.** Most local later `ADL.DRV` files are not
  one of ScummVM's recognized embedded-bank sizes, but those games supply
  patch resource 3. A game with neither must be a visible unsupported-bank
  result, not a guessed offset scrape.
- **Multiple simultaneous SCI sounds.** The present engine audibly serves
  one player object at a time. The new sequencer should not accidentally
  promise polyphonic sound-object mixing until SCI priority/preemption
  behavior is separately specified and tested.
- **Cue latency.** A 100–250 ms lookahead can make generated audio trail
  script cues if cue release uses generated rather than played frames.
  The stage-5 tests must choose and document the audible-frame convention.
- **Digital sample choice.** Sierra and ScummVM do not always prefer a
  sample merely because it exists. Stage 8 needs title-level fixtures so a
  sample does not replace intended FM/Tandy effects indiscriminately.
- **MT-32 scope creep.** Patch 1 parsing is straightforward compared with
  shipping Munt. ROM discovery, native builds, SysEx pacing, CPU use, and
  LCD/reverb semantics belong in the follow-up MT-32 plan.

## Definition of done for the Sound Blaster first release

- An SCI game with a supported bank can be switched among current PSG,
  AdLib FM, and Sound Blaster FM+digital-sample modes without restarting the
  application, with no stuck notes after switching.
- PQ2 and KQ4 play recognizable, correctly pitched and timed music/SFX with
  their own game-supplied instruments; a late 96-instrument title also does.
- Script cues, loops, pause/stop, master volume, and save/restore behavior
  match the legacy path's observable contract.
- The debug UI can explain why a channel sounds as it does from resource to
  register writes.
- AGI FM presets are available but are never selected accidentally for an
  SCI title, and exact Tandy noise remains available in every AGI preset.
- Missing or malformed banks fail visibly and recover to the configured
  fallback instead of crashing, hanging a voice, or silently playing the
  wrong instruments.

## Sources and local evidence

Implementation should start from these inspected sources, in this order:

- Local ScummVM SCI source in `reference_docs/scummvm_sci-2026-09`,
  especially `sound/drivers/adlib.cpp`, `sound/drivers/mididriver.h`,
  `sound/midiparser_sci.cpp`, and `resource/resource_audio.cpp`.
- The SCI0 sound format specification at
  <https://wiki.scummvm.org/index.php?title=SCI/Specifications/Sound/SCI0_Resource_Format>.
- ScummVM's user-level device distinctions at
  <https://docs.scummvm.org/en/latest/advanced_topics/understand_audio.html>.
- Nuked OPL3's public C interface at
  <https://raw.githubusercontent.com/nukeykt/Nuked-OPL3/master/opl3.h>
  and its LGPL-2.1 text at
  <https://raw.githubusercontent.com/nukeykt/Nuked-OPL3/master/LICENSE>,
  retained as an accuracy/oracle reference rather than the chosen core.
- DOSBox Staging's statement that its NukedOPL path is intended to be
  cycle-accurate at
  <https://www.dosbox-staging.org/0.83/manual/sound/sound-devices/adlib/>.
- libADLMIDI's feature and mixed-license documentation at
  <https://raw.githubusercontent.com/Wohlstand/libADLMIDI/master/README.md>,
  considered and not selected for the first implementation.
- Munt's library and C-interface documentation at
  <https://raw.githubusercontent.com/munt/munt/master/mt32emu/README.md>
  and
  <https://raw.githubusercontent.com/munt/munt/master/mt32emu/src/c_interface/c_interface.h>,
  retained for the separate MT-32 stage.
- Yamaha YM3812/YMF262 data sheets obtained during implementation of the
  chip step. The register implementation should cite the exact data-sheet
  revision in code comments where a non-obvious timing/table choice is made.
