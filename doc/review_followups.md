# Code Review Follow-ups — Prioritized Work Plan

Created 2026-11-18 from a full-project review of branch `sci0` @ `84edcaf`
(clean tree, == `origin/sci0`, 65 ahead / 0 behind `main`).

Method: eight subsystem reviews (tooling/docs, core/loader/domain, picture
+ shared graphics + SCI loader, AGI logic/engine, SCI VM/kernel, audio, UI,
tests/quality), followed by an adversarial re-check of the 10
highest-severity claims against the cited code (9 verified, 1 overstated,
0 refuted). Observed at review time: `dart analyze` → "No issues found";
`flutter test test/core/lzw_test.dart` passed. The full test suite,
coverage, and `flutter pub outdated` were **not** run — see
[Unverified / not reviewed](#unverified--not-reviewed).

## How to work this list

- Work top-down. Ranks 1–7 (P0) before any new SCI feature work.
- Every fix lands with a test naming the exact behaviour in its
  "Verify" line. No fix is done on a green self-authored check alone —
  run the repo's own scoped tests for the touched area.
- Verification gates per `AGENTS.md` §3 (always, before calling a task done):
  - `dart analyze` (must stay at zero issues)
  - SCI-only changes: `flutter test test/sci/`
  - AGI-only changes: `flutter test`
  - Shared graphics (`DisplayProfile`, slicer, compositor, atlas, CRT,
    `EgaColors`): both suites
  - New SCI tests go under `test/sci/`; shared graphics tests under
    `test/graphics/` (to be created) or `test/picture/`
- Check the box and append the landing commit short-hash when an item ships.

Effort key: S = hours, M = a day or two, L = multi-day / architectural.

---

## P0 — fix now

- [x] **1. [DEBT/S] Make the test gate honest; add CI.** *(2026-11-19: skip
  helper `test/support/reference_games.dart` + migration of 97 silent
  returns and 15 unguarded SCI files; required-games documentation in
  `doc/testing.md`; CI in `.github/workflows/ci.yml` — written but not
  yet run on GitHub (unpushed). Local clean-copy run without game data:
  742 passed / 198 skipped / 2 failed, both pre-existing — see
  Unverified.)*
  No `.github/` exists despite the `AGENTS.md` §3 analyze+test mandate.
  66 of 199 test files silently `return` (counted as pass) when the
  gitignored `reference_games/` tree is absent (e.g.
  `test/ui/sq1_room65_keypad_test.dart:17`); 15 SCI test files throw
  unguarded without it (`test/sci/sci_pic_pq2_test.dart:9`); 110 files
  depend on that tree at all.
  Fix: shared helper that calls `markTestSkipped` (as in
  `test/sci/sci_boot_test.dart:15`) used by every `reference_games` test;
  add macOS CI running `dart analyze` + the non-fixture tests.
  Verify: a clean checkout (no `reference_games/`) reports skips, not
  passes, and CI is green.

- [x] **2. [BUG/S] Inventory selection is always cancelled.** *(2026-11-19:
  single `onDone(int?)` callback; GameScreen flag-13 regression test.)*
  `_handleSelectCurrent` (`lib/ui/widgets/inventory_dialog.dart:166`)
  calls `onSelect` then `onClose`; both are wired to `closeInventory`
  (`lib/ui/screens/game/game_screen.dart:731`), so the second call
  rewrites `var25 = 255` (`lib/engine/agi_game_engine.dart:927`).
  (The suspected double-resume is mostly guarded by `hasPendingInput`;
  the `var25` clobber is the real harm.)
  Fix: replace the two callbacks with a single `onDone(int?)`.
  Verify: GameScreen-level flag-13 widget test asserts `var25` equals
  the selected item.

- [x] **3. [BUG/S] SCI restore splits globals from script-0 locals.** *(2026-11-19:
  in-place restore into script0 locals, alias asserted in save/load test.)*
  `restore` (`lib/sci/engine/sci_game_state_snapshot.dart:606`) assigns
  `List.from(globals)`, breaking the `globals == script0.locals` alias
  established in `lib/sci/engine/sci_seg_manager.dart:183`; `lag` and
  `lal` diverge after any restore.
  Fix: restore in place into `s0.locals` and keep `globals` identical
  to it.
  Verify: save/load test writes via `lal`, reads via `lag`.

- [x] **4. [BUG/S] AGI interpreter freezes permanently after a sync throw.** *(2026-11-19: try/catch clears `_isExecuting`; tick sync-error path skips success cleanup; `_runLoop` survives tick throws. Regression tests in interpreter + engine suites.)*
  `_runExecutionLoop` (`lib/logic/interpreter/agi_interpreter.dart:137`)
  clears `_isExecuting` only on async paths; a synchronous throw leaves
  it set forever. The engine tick body
  (`lib/engine/agi_game_engine.dart:1050`, `:1210`) is likewise
  unguarded while `_isRunning` stays true, so `start()` no-ops.
  Fix: try/finally to clear `_isExecuting`; guard the whole tick and use
  a single error path (the sync path at `:1231` currently falls through
  to success cleanup, wiping f2/f4/controllers/input).
  Verify: fault-injection test throws inside a step, then the next tick
  resumes.

- [x] **5. [BUG/S] Audio sink re-initialization throws `StateError`.** *(2026-11-19:
  device-only teardown + controller recreation in all three sinks,
  idempotent dispose; new macOS lifecycle test.)*
  `initialize()` (`lib/audio/mac_audio_queue_sink.dart:271`) calls
  `dispose()`, which closes `_statusController`, then adds to it;
  `dispose()` is also not idempotent. Same shape in
  `lib/audio/windows_wave_out_sink.dart:287`.
  Fix: dispose-queue-only helper; recreate the controller on init; make
  `dispose()` idempotent.
  Verify: lifecycle test init → dispose → init → play on macOS (the
  macOS sink currently has zero tests; the only FFI test,
  `test/audio/windows_wave_out_sink_test.dart:10`, vacuously passes
  off-Windows).

- [x] **6. [BUG/M] Early SCI0 (KQ4-SCI) kernels misdispatch.** *(2026-11-19: REFUTED by boot trace — KQ4 calls NewList at raw 0x32, identical numbering to late SCI0 (ScummVM inserts FileIO at 0x29 for both versions). No production change; KQ4 boot test now pins kernel ids/names so a future remap breaks loudly, and the "unshifted kernel IDs" claims in `AGENTS.md` / `doc/sci0_reference_index.md` were corrected. The original finding mistook the selector-stride/script-header differences for a kernel shift.)*
  Only the late (FileIO-shifted) table is registered
  (`lib/sci/engine/sci_kernel.dart:568`); there is no VOCAB.999 load and
  no `isEarlySci0` remap, and `lib/sci/engine/sci_vm.dart:541` passes
  the raw `callk` id. Unshifted ids ≥ 0x29 hit the wrong kernels.
  Fix: load VOCAB.999 or remap early ids at registration.
  Verify: KQ4 boot test asserts specific kernel dispatch, not merely
  `stepCounter > 0` (`test/sci/sci_kq4_boot_test.dart:61`).

- [x] **7. [BUG/S] Sound player: play-after-dispose and stale sample rate.** *(2026-11-19:
  disposed guard + re-init on sample-rate change, with player tests.)*
  `play()` (`lib/audio/agi_sound_player.dart:161`) lacks the
  `_isDisposed` guard the other transport methods have, so it
  re-initializes a disposed sink (hitting item 5's `StateError`); and
  the sink is only initialized when uninitialized (`:183`), so a later
  `play()` at a different `sampleRate` renders at the wrong pitch/speed.
  Fix: early return when disposed; re-init when the rate differs.
  Verify: unit tests for both cases with a fake sink (existing
  `test/audio/sound_muted_timing_test.dart:101` covers stop/pause only).

## P1 — next

- [x] **8. [BUG/S] Decompressors silently return short data.** *(2026-11-19: AGI EOF size check + prefix-chain caps, SCI LZW terminator exemption removed (all 763 PQ2 resources still pass), Huffman numNodes==0 throws; truncation + width-growth tests.)*
  Early EOF (code 257) returns a truncated buffer with no size check in
  `lib/core/utils/lzw_decompression.dart:54` (final check at `:115`
  bypassed) and silently zero-pads in
  `lib/sci/loader/decompressor_lzw.dart:139`, while Huffman throws;
  `numNodes == 0` throws `RangeError` instead of a typed exception in
  `lib/sci/loader/decompressor_huffman.dart:62`. Short results are then
  cache-poisoned by callers.
  Fix: throw the typed decompression exception on any size mismatch,
  consistently across AGI LZW, SCI LZW, and Huffman.
  Verify: truncated-stream test per decompressor. (Also add the missing
  dictionary-growth / code-width-boundary cases — AGI LZW currently has
  one literal-only test, `test/core/lzw_test.dart:7`.)

- [x] **9. [BUG/S] GameScreen callbacks outlive the State.** *(2026-11-19: dispose clears all three session callbacks; initState closures guard on `mounted`; regression test with externally owned session.)*
  `onSave`/`onRestore`/`onRestartGameRequested` capture this State's
  `context` at `lib/ui/screens/game/game_screen.dart:138` and are never
  cleared in `dispose()` (`:152`); with an externally owned session
  (`disposeSession: false`) they later call `showDialog` on a defunct
  context.
  Fix: `mounted` guard + null the callbacks in `dispose()`.
  Verify: widget test that disposes the screen, then triggers each
  callback, and observes no throw.

- [x] **10. [BUG/M] Saves are non-atomic and unversioned (both engines).** *(2026-11-19: tmp-file + rename writes, slot range 1..12 validated, save-version major checked in both fromJson (missing version still accepted for legacy saves), AGI fromJson casts made num-defensive; SCI kernel save/restore/check callbacks convert failures to a clean false instead of throwing into the VM. Descoped by lead decision: no game-identity field (no stable id exists; saves live under a per-game saveDirectory) and no transactional mid-restore rollback — parse+validate completes before any engine mutation, but a throw during room reload inside restore can still leave partially applied state. The capture/callStack parentheticals below remain open.)*
  `writeAsStringSync` writes directly onto `slot_N.sav`
  (`lib/engine/state/game_state_serializer.dart:135`,
  `lib/sci/engine/sci_game_state_serializer.dart:140`), so a crash
  mid-write destroys the previous good save. The stored `version` is
  never validated and no game identity is checked before live state is
  reset (`lib/domain/game_state_snapshot.dart:743`,
  `lib/sci/engine/sci_game_state_snapshot.dart:850`); hard `as int`
  casts (`game_state_snapshot.dart:245`) turn corrupt saves into
  `TypeError`s, and AGI `restore()` mutates memory before the room
  reload completes.
  Fix: write temp file + rename; validate version/game before any
  mutation (validate-then-apply); uniform defensive numeric parsing;
  validate slot range 1..12.
  Verify: kill-mid-write and corrupt-JSON tests keep the old save
  loadable and leave live state untouched. (Related, same files: AGI
  `capture` only saves drawn/animated objects but `restore` resets all;
  serialized `callStack` is never rebuilt on restore — either restore
  frames or drop the field and document scan-boundary-only saves.)

- [x] **11. [BUG/M] SCI hunk allocator wraps at 64 KiB.** *(2026-11-19: coalescing free-range first-fit allocator, bump only within 64 KiB else `SciException`, `rebuildHunkFreeList` after snapshot restore; offset-pool exhaustion returns -1 → newList/newNode return nullReg, cloneObject throws, instead of aliasing offset 1. Allocator tests incl. 65,535-node exhaustion.)*
  `allocHunk` (`lib/sci/engine/sci_seg_manager.dart:912`) advances
  `nextHunkOffset` monotonically and `freeHunk` never reclaims it, but
  `SciReg.pointer` (`lib/sci/engine/sci_types.dart:37`) masks offsets
  `& 0xFFFF`; after 64 KiB of cumulative `allocString` (per typed
  input / word-fail) lookups miss or collide. Related:
  `_Offset16Pool.alloc` (`sci_seg_manager.dart:1089`) returns offset 1
  on exhaustion, aliasing a possibly-live clone/list/node.
  Fix: free-list reuse for hunks (pool-style); on pool exhaustion throw
  or return a sentinel that kernels translate to `nullReg`.
  Verify: alloc/free loop exceeding 64 KiB cumulative keeps every live
  hunk readable and distinct.

- [x] **12. [BUG/M] Truncated bytecode/PIC escapes as `RangeError`.** *(2026-11-19: AGI action pre-check via the disassembler's operand table (cross-validated against interpreter reads — no opcode reads beyond its template), test-section `_requireBytes`, SCI guarded readers in opcode decode + both pic interpreters incl. FE sub-op defaults; truncation tests per decoder.)*
  Operand reads are unchecked in
  `lib/logic/interpreter/agi_interpreter.dart:510` (only the opcode
  byte is checked, `:211`), in `decodeInstruction`
  (`lib/sci/engine/sci_opcodes.dart:213`), and pervasively in
  `lib/sci/picture/sci_pic_interpreter.dart:38` (plus the step twin at
  `sci_pic_step_interpreter.dart:68`, which also lacks a default case
  and silently desyncs). The AGI picture interpreter already
  bounds-checks (`lib/picture/pic_vector_interpreter.dart:290`) — match
  it.
  Fix: shared `need(n)` / guarded reader per decoder; throw
  `AgiException`/`SciException`, never `RangeError`.
  Verify: truncated LOGIC / SCRIPT / PIC fixtures throw the typed
  exception. (Interacts with item 4: once decoding throws typed errors,
  the interpreter loop must survive them.)

- [x] **13. [BUG/M] No AGI instruction budget — a looping script freezes the UI.** *(2026-11-19: per-cycle `maxStepsPerCycle` budget, default 1,000,000, throwing `AgiException`; GOTO-loop and straight-line counter tests; real-game boots unaffected at the default.)*
  The execution loop (`agi_interpreter.dart:143`) has a rescan budget
  but no step budget; a backward-GOTO loop spins synchronously forever.
  Fix: max steps per cycle, then yield or raise a typed error.
  Verify: a deliberately looping script returns control within one tick.

## P2 — soon

- [ ] **14. [DEBT+ENH/L] Replace 16-slice compositing with a
  priority-checking fragment shader.** *(In progress 2026-11-19:
  spike GO + `shaderComposited` mode wired end-to-end
  (priority textures, painter, widget shader ownership, AV settings
  entry, add.to.pic invalidation). Parity goldens byte-exact vs
  slices (synthetic AGI bands, text-in-band, real PQ2 pic). Field
  tested seam-free including AGI text overlays; at 60 Hz / 4:3 the
  user measured ~15% GPU for native priority-shader compositing
  versus ~25% for slices, and ~25% versus ~35% with CRT enabled,
  with CPU about equal. `shaderComposited` is therefore now the
  default game render mode, with slices retained as automatic
  fallback. Remaining before checking off: soak in the default
  configuration, then delete the slice game path and stop computing
  slices for gameplay (diagnostic slicing remains). Software-raster
  proxy (60 renders, PQ2 pic 1): slices 1021 ms vs shader 224 ms at
  4x scale; PQ2 pics average only 4.1 active slices (max 13).)*
  See [Graphics pipeline migration](#graphics-pipeline-migration-rank-14)
  below for the full plan, rationale (including the measured CPU
  comparison), spike risks, and acceptance gate. Do not start until
  ranks 1–13 are landed; rank 1's honest test gate is what makes the
  golden-image acceptance tests meaningful.

- [x] **15. [BUG/M] Corrupt resources silently yield partial data.** *(2026-11-19: all sites throw `CorruptResourceException`/`SciCorruptResourceException`. WORDS.TOK keeps exactly one legal tolerance — the lone trailing prefix byte real Sierra files end with (reference-parser semantics); four invalid synthetic fixtures were corrected to valid empty dictionaries. SCI side verified against all 10 real maps and all 763 PQ2 volume records.)*
  Truncation is accepted and papered over in:
  `lib/loader/parsers/words_parser.dart:44` (partial dictionary),
  `lib/loader/parsers/objects_parser.dart:74` (blank-named objects),
  `lib/loader/parsers/logic_parser.dart:31` (missing messages),
  `lib/loader/resource_directory.dart:159` (unvalidated V3 header
  offsets; negative counts; `find*` also accepts negative numbers at
  `:188`), `lib/sci/loader/volume.dart:217` (header id/length never
  checked against the map entry — a bad offset returns the *wrong*
  resource silently), `lib/sci/loader/resource_map.dart:68` (missing
  `0xFFFFFFFF` sentinel accepted), `lib/core/utils/pic_compression.dart:9`
  (`reslen == 0` → `RangeError`; header length never enforced).
  Fix: bounds/sentinel/id checks, throwing `CorruptResourceException`
  consistently (today only the sound parser uses it —
  `lib/core/errors/agi_exceptions.dart:23`).
  Verify: one truncation/corruption test per parser.

- [x] **16. [BUG/S] Cache aliasing corrupts shared buffers.** *(2026-11-19: unmodifiable views from view/volume caches and dictionary groups (caller audit found zero writers, so no call-site copies needed), duplicate-word group consistency, mirror-cycle and dimension-mismatch now `AgiException` instead of stack overflow / `RangeError`. Parse-time mirror validation deliberately not added — runtime guards cover both parsers.)*
  `getPixels` (`lib/domain/sierra_view.dart:60`) and `getResource`
  (`lib/loader/volume_manager.dart:131`) return the cached mutable
  buffer itself; any caller writing into it corrupts the cache for all
  users. `Dictionary.idToWords` (`lib/domain/dictionary.dart:17`) has
  the same shape (live list). Related in `sierra_view.dart:27`:
  mirrored cels resolve recursively with no visited set — a 2-loop
  mirror cycle stack-overflows.
  Fix: return a copy or an unmodifiable view; validate mirror loops at
  parse time and detect cycles.
  Verify: mutate-a-returned-buffer test leaves the cache intact; cyclic
  mirror fixture fails at parse with a typed error.

- [ ] **17. [DEBT/L] SCI parser accepts any word order (documented Stage 14).**
  `_kParse` (`lib/sci/engine/sci_kernel.dart:2201`) keeps only
  `candidates.first`, dropping homonym groups from
  `lib/sci/engine/sci_vocab.dart:108`, and VOCAB.900 GNF is unported,
  so any known-token order sets `parserIsValid` and `syntaxFail` never
  fires on grammar. `_kSetSynonyms` (`:2281`) also never clears, so
  room synonyms accumulate across rooms. Ranked below the undocumented
  bugs above because it is already tracked in
  `doc/sci0_deferred_cleanup.md:40`.
  Fix: port ScummVM `grammar.cpp` / `said.cpp`; clear synonyms before
  walking the collection.
  Verify: wrong-order input sets `syntaxFail` in a PQ2 fixture; synonyms
  from room A do not match in room B.

- [ ] **18. [ENH/M] FileIO/system kernels stubbed to 0 (documented Stage 15).**
  `FOpen`/`FPuts`/`FGets`/`FClose` (0x29–0x2C), `DoAvoider` (0x55),
  `GetCWD`/`CheckFreeSpace`/`ValidPath`/`DeviceInfo`/`GetSaveDir`/
  `ShakeScreen`/`Joystick` are `_kStub` returning 0
  (`lib/sci/engine/sci_kernel.dart:623`, `:713`). `GetSaveDir`/`GetCWD`
  must write a buffer, and 0 from `CheckFreeSpace`/`ValidPath` reads as
  failure to Sierra save dialogs.
  Fix: benign per-op returns first (write save dir, free-space > 0,
  valid = 1); sandboxed FileIO on the save directory second (ScummVM
  `kFileIO` model); port `kDoAvoider`.
  Verify: kernel unit test per op; Avoider test mirroring
  `test/sci/sci_set_jump_test.dart`.

- [ ] **19. [BUG/S] SCI dithering toggle is a no-op; view palette ignored.**
  `sciEnableDithering` (`lib/ui/models/user_settings.dart:13`) is
  persisted and shown (`lib/ui/widgets/av_settings_dialog.dart:910`)
  but no painter reads it. Similarly `paletteOffset` is parsed and
  stored (`lib/sci/view/sci_view_parser.dart:47`) but consumed nowhere,
  so SCI1-EGA paletted views render with wrong colors silently; and the
  parser rejects only `flags == 0x80` exactly (`:49`) though 0x80 is a
  bit — `0xC0` slips through and RLE-decodes garbage.
  Fix: wire the toggle to the undithered visual or remove it; apply
  the 8×16 palette mapping or reject `paletteOffset != 0` loudly;
  test `(flags & 0x80) != 0`.
  Verify: toggling changes rendered pixels in a pic test; `0xC0`
  fixture is rejected.

## P3 — later / debt sweep

- [ ] **20. [DEBT/S] `fetch_llama_server` unverified download.**
  `tool/fetch_llama_server.dart:127` downloads and extracts an
  executable release asset with no SHA-256/signature check.
  (Adversarial re-check downgraded this from P1: dev-run tool over
  HTTPS from github.com, not shipped runtime code.)
  Fix: pin a per-asset SHA-256 next to the `--pin` tag; verify before
  extract. Verify: tampered asset aborts the tool.

- [ ] **21. [DEBT/M] Stale docs, god files, swallowed errors.**
  `README.md:18` is Gemini-era (API key, "570+" tests, no SCI mention;
  actual: local EmbeddingGemma per `doc/local_ai_setup.md`, 199 test
  files / ~933 tests). `doc/sci0_dual_engine_architecture.md:185` calls
  landed Stage 13 "Next" and lists implemented kernels as stubs.
  `Features_Roadmap.md` is a second, AGI-only source of truth.
  `lib/engine/agi_game_engine.dart` (3,919 lines),
  `lib/sci/engine/sci_kernel.dart` (3,423), and
  `lib/ui/widgets/debug_inspector_dialog.dart` (3,407) dominate review
  blast radius. 49 empty `catch (_) {}` in `lib/` swallow load/parse
  errors. `analysis_options.yaml:10` is stock `flutter_lints` (no
  strict casts/inference; `avoid_print` left off with 9 `print()`s in
  `lib/`, all `kDebugMode`-guarded). `pubspec.yaml:2` still says
  "A new Flutter project."; no LICENSE/CHANGELOG; android/ios/linux/web
  runners are committed but excluded from analysis and unsupported.
  `AGENTS.md §2` undersells `lib/sci/` and §3 references a nonexistent
  `test/graphics/`.
  Fix: rewrite README; correct the stage table; archive or fold in
  `Features_Roadmap.md`; split kernel by family and engine by
  lifecycle/motion behind existing facades; log (with context) or
  narrow every empty catch; enable `avoid_print` + strict modes and
  fix fallout incrementally; set real pubspec metadata; delete or
  document unsupported platform runners; refresh `AGENTS.md`.
  Verify: `dart analyze` clean under the stricter options; doc claims
  grep-consistent with `git log`.

### Next tier (queued after the ranked items)

Audio: check every FFI `OSStatus`/MMRESULT
(`mac_audio_queue_sink.dart:317`, windows `:389`); paused-seek desync
(`agi_sound_player.dart:254` vs `:221`); flush-while-playing stall
(suspected, mac `:412` / windows `:447`); finish gated on wall-clock
Stopwatch instead of `playedFrames`, truncating tails (`:307`);
whole-sound synthesis on the UI isolate (`:189`) — move to `Isolate.run`
or chunk; CSound exporter emits silent notes → divide-by-zero
(`csound_builder.dart:36`); SCI voices beyond 3 silently dropped in
tandy/enhanced render (`pcm_synthesizer.dart:200`); `_softLimit` is a
hard clamp (`:287`); `setVolume` while muted unmutes audibly (`:271`);
unconditional `dart:io`+FFI imports break web builds (`:2`).

AGI engine/logic: opcodes 170–181 skipped on guessed arg counts
(`agi_interpreter.dart:1772`) — centralize lengths with the decoder
table; sync error path wiping input state (`agi_game_engine.dart:1231`);
dialog completers not completed on restore (`:2651`, snapshot `:636`);
engine re-implements `said` matching instead of delegating to the
unit-tested `AgiSaidMatcher` (`:3842` vs
`lib/engine/parser/agi_said_matcher.dart:81`); movement collision tested
only at the destination — large `step.size` can tunnel over 1px control
lines (suspected, `:2299`); `CollisionDetector` passes `stepSize` as
width/height and is test-only while the engine inlines a second
implementation (`lib/engine/motion/collision_detector.dart:258`);
test opcode 0 decodes silently
(`lib/logic/disassembler/instruction_decoder.dart:287`).

Graphics/UI: per-pixel priority rescan is O(n·height) worst-case in the
AGI slicer (`picture_slicer.dart:57` → `priority_buffer.dart:77`) —
precompute effective priorities bottom-up in one pass (also the first
step of rank 14); duplicated full/step pic decoders have already
diverged (`pic_step_interpreter.dart:484` vs
`pic_vector_interpreter.dart:290`; SCI step drops FE08 priority bands);
atlas `maxAtlasDimension` is defeated by growing past the cap
(`view_texture_atlas.dart:424`); `Paint()` allocated per sprite and a
fresh actor list per frame (atlas `:197`, playfield `:774` — also
`_buildActorSprites` runs inside `paint`, triggering atlas builds as a
paint side-effect: move actor computation into the notify path);
20 Hz sidebar/dialog rebuilds via coarse session listenables
(`game_screen.dart:671`); `strictIntegerScaling` overflows viewports
under 320×240 (`game_playfield_widget.dart:249`, copied in three
dialogs — extract one `PlayfieldFit` helper and dedupe the 4:3 math);
pic browser accumulates every scrubbed picture until dispose
(`pic_browser_screen.dart:89`); failed directory rescan keeps a closed
loader in state (`game_launcher_provider.dart:110` vs `:187`); key
handling swallows `KeyRepeatEvent` (no held-backspace repeat,
`game_screen.dart:240`) and sidebar text fields can leak keystrokes
into the game (suspected, `:660`); debug inspectors pause and never
resume (`debug_inspector_dialog.dart:21`,
`sci_debug_inspector_dialog.dart:16`); SaveLoad confirm has no
re-entrancy guard (suspected double-pop, `save_load_dialog.dart:185`).

Tests: synthetic VOL/SCRIPT/PIC builders + committed mini-fixtures to
replace `reference_games` dependence (only 3 committed fixtures today);
pixel-value goldens for SCI pics (`sci_pic_pq2_test.dart:41` checks
dimensions only); exact-boot assertions
(`sq1_intro_test.dart:16` accepts 4 rooms including un-booted 0);
wall-clock-sleep tests → fake clock / awaited completers
(`sound_muted_timing_test.dart:44`, `sci_pic_canvas_test.dart:40`);
direct unit tests for `sierra_view`, pic canvases/rasterizer, macOS
audio sink, `SciDebugInspectorDialog`, `SidebarSlideoutPanel`.

Credit where due (do not regress): playfield repaint is listener-driven
rather than rebuild-driven; browsers and both inspectors dispose
controllers/timers correctly; `SaveLoadDialog` pause/resume and
mounted-after-await handling are correct.

---

## Graphics pipeline migration (rank 14)

### Where we are

Every picture is decomposed once into up to 16 full-frame 320×200 RGBA
textures, one per priority band (`lib/picture/picture_slicer.dart`),
retained as `PictureSlice`s with both CPU bytes and a cached
`ui.Image` (`lib/domain/picture.dart:37`). The compositor
(`lib/ui/widgets/agi_picture_canvas.dart:779`) draws slice *P*, then
actors bucketed at priority *P*, for *P* = 0..15 — which exactly
reproduces Sierra's per-pixel test "blit sprite pixel iff
PriorityMap(x, y) ≤ P" (`doc/picture_rendering_strategy.md:10`).
`add.to.pic` re-slices only dirty bands via `sliceSinglePriority`
(`lib/engine/agi_game_engine.dart:3446`).

The original rationale was avoiding a CPU→GPU copy every frame.
Measured 2026-11-18 on the dev machine (Dart 3.13.5, macOS arm64;
scratch benchmark, not in-repo): a full CPU composite of one
320×200 frame (background + 10 priority-masked sprites, reused
buffer) costs ~159 µs; background-only ~113 µs; the SCI slicer loop
~287 µs once per picture. A flat frame is 250 KiB → ~5 MB/s upload at
the 20 Hz tick. Neither number is near a bottleneck on the macOS /
Windows desktop targets, so bandwidth alone does not justify the
16-layer design. Its real costs:

- **Overdraw:** each slice is a full-frame `drawImage` scaled to the
  widget; a typical picture blends ~12–16 screen-sized, mostly
  transparent quads per repaint (tens of millions of fragments at
  Retina sizes), versus 1 for a flat image. (Arithmetic estimate —
  profile in-app before/after the migration to confirm.)
- **Memory:** up to 16 × 250 KiB × 2 (CPU `rgbaBytes` retained after
  upload + GPU texture) ≈ 8 MB per picture, versus ~0.5 MB flat;
  multiplied wherever pictures are retained (pic browser).
- **Complexity/lifecycle:** up to 16 async `decodeImageFromPixels`
  per room, dispose-during-decode guards, flat-image fallback until
  slices land, and the `add.to.pic` dirty-band machinery.

Its real benefits, which any replacement must preserve: retained GPU
textures with synchronous paint (Flutter has no mutable-texture /
TexSubImage API, so a CPU-composite design would need a fresh async
`ui.Image` every tick — a frame of latency plus alloc/dispose churn);
GPU texture-atlas sprites; exact priority occlusion including
per-priority interleaved playfield text; and slice isolation in the
pic browser / step replay workbench.

### Target design

One flat background texture + one priority texture per picture;
actors drawn as rects with a fragment shader that samples the atlas
and the priority texture and discards fragments where
`actorPriority < priorityAt(pixel)`.

1. **Priority texture.** 320×200, priority encoded in one channel
   (value = pri / 15), nearest sampling. AGI stores *effective*
   priority (control lines ≤ 2 resolved by downward scan,
   `priority_buffer.dart:77`), precomputed once per picture in a
   single bottom-up O(n) pass. SCI stores the raw priority byte
   (`DisplayProfile.sci0`, no scan). The existing debug priority-map
   image cannot be reused — it encodes EGA colors, not values.
2. **Shader.** New `shaders/priority_sprite.frag` registered next to
   `shaders/crt_effect.frag` in `pubspec.yaml:65`, loaded with the
   same `FragmentProgram.fromAsset` pattern as
   `lib/ui/shaders/crt_shader_loader.dart:26`; one `FragmentShader`
   instance owned/disposed by widget State, following
   `CrtShaderOverlay` (`agi_picture_canvas.dart:1013`). Per-sprite
   uniforms: atlas source rect, destination rect in 320×200 playfield
   coordinates, actor priority, mirror flag — all already computed by
   `ViewTextureAtlas.drawEntry` (`lib/ui/core/view_texture_atlas.dart:180`).
   Non-atlas (standalone cel image) sprites take the same path with a
   full-image source rect.
3. **Draw order.** Flat background first, then actors in the existing
   `PlayfieldActorSprite.compareDrawOrder` (priority, updating,
   sort-Y) in a single pass. Actor-vs-actor ordering is preserved by
   draw order; the 16-bucket interleave loop is deleted. Fixed /
   ignore-priority objects pass priority 15 (or an explicit
   no-test uniform) — confirm against `AnimatedObject.effectivePriority`
   (`lib/domain/animated_object.dart:113`) during the spike.
4. **`add.to.pic`.** Burn into visual + priority buffers as today,
   then re-upload only the flat + priority textures (2 decodes).
   Delete the `sliceSinglePriority` call path from the engine.
5. **Slicer becomes diagnostics-only.** Pic-browser slice isolation
   (`pic_browser_screen.dart:37`) and step replay generate one slice on
   demand via the existing slicer; the game path computes no slices
   (the `computeSlices: false` paths in
   `lib/sci/picture/sci_pic_canvas.dart:529` /
   `lib/picture/pic_canvas.dart:85` become the only game paths).
   Undithered SCI rendering uses the alternate flat texture, as the
   current `unditheredVisual` render mode already does.
6. **Fallback & rollout.** New path behind the existing
   `AgiPictureRenderMode` (e.g. `shaderComposited`); if the
   `FragmentProgram` fails to load (tests, unsupported backend),
   fall back to the current slice compositor. Ship opt-in → default
   after the acceptance gate → delete slice game path after a soak.

### Spike first (resolve before migrating anything)

- **fragCoord → UV mapping** under the painter's `canvas.scale` to
  320×200 logical space (`agi_picture_canvas.dart:293`): derive both the
  atlas UV and the priority-texture UV from the same playfield-space
  position; prove texel-exact sampling (no half-texel offset) at
  integer and fractional scales, with screen shake applied.
- **Priority equality edge:** slice compositing draws the actor
  *after* slice P, so the actor wins where `priorityAt == P`. The
  shader must discard only on `priorityAt > actorPriority`. Encode
  priorities so float comparison is exact (compare
  `floor(sampled * 15.0 + 0.5)` or store pri/255 steps well above
  sampler precision noise); unit-test the equality band explicitly.
- **Playfield text:** text glyphs/fills are currently interleaved per
  priority band (`agi_picture_canvas.dart:787`), and `TextPainter`
  output cannot trivially run through a discard shader. Options:
  (a) draw playfield text on top — first verify against Sierra
  behaviour for `print.at`-style text overlapping priority-15
  foreground; (b) mask text with a priority-derived clip. Decide from
  reference behaviour, do not guess. Status-line/menu/window text is
  unaffected (already drawn on top).
- **Mirrored cels:** atlas drawing flips via canvas transform today
  (`view_texture_atlas.dart`, flipped branch); under the shader, flip
  is a source-rect mirror in UV space — verify against a mirrored
  loop fixture.
- **Shader-less environments:** widget tests and any backend without
  fragment-shader support must take the slice fallback; the render
  mode switch and `FragmentProgram` load failure path must both be
  tested.

### Acceptance gate (all required before it becomes the default)

- Pixel-identical output vs the current slice compositor (golden
  images, zero differing bytes) for: an actor crossing priority-15
  foreground; an actor standing on water/control lines (AGI effective
  priority); a fixed-priority object; at least one AGI room and one
  SCI0 room (PQ2). Text cases included once the text decision lands.
- `flutter test test/sci/` **and** full `flutter test` pass (shared
  graphics rule, `AGENTS.md` §3); `dart analyze` clean. Golden tests
  live in `test/graphics/` and must use committed synthetic fixtures,
  not `reference_games` (depends on rank 1 honesty so they cannot
  silently pass).
- Profiled repaint on the dev machine shows the fullscreen-quad count
  per repaint dropped from ~12–16 to 1 + sprites, with no new
  per-frame allocations in `paint`.

### Spike findings (2026-11-19) — GO for migration

Prototype landed and is kept (`shaders/priority_sprite.frag`,
`lib/ui/shaders/priority_sprite_shader.dart`, goldens in
`test/graphics/priority_sprite_shader_test.dart` — 6 tests, all pass;
not yet wired into the game painter):

- **fragCoord mapping settled:** `FlutterFragCoord()` arrives in
  local (playfield) space through the inverse canvas transform —
  texel-exact at scale 1 and integer scale 3 with no scale uniform,
  and correct under a pre-scale translate. Production shake
  translates in device pixels before the painter's inner scale
  (`_GamePlayfieldPainter`), which the passing shake case encodes.
- **Equality edge:** discard only on `priAt > actorPri` with
  `priAt = floor(r*15 + 0.5)` on `pri*17` encoding — byte-exact
  against a CPU oracle including the pri==actor band, atlas
  sub-rects, transparent texels, and mirrored cels.
- **Fractional scale:** at 2.5× interior pixels are byte-exact;
  the destination-rect boundary ring is coverage-blended by
  rasterizer AA (same edge behaviour as scaled `drawImage` today).
  The golden asserts zero interior diffs and blend-confinement on
  the ring. SkSL (flutter-test backend) has no `discard`; emitting
  transparent black under src-over is the equivalent used.
- **Playfield text — no masking needed.** Slice-model per-cell
  interleaving nets out to: text is never occluded by background
  (its band is the background's own priority, drawn after that
  slice), and actors draw over text exactly when
  `actorPri >= backgroundPri` — the shader's own test. So the
  migrated order is flat background → playfield text fills+glyphs
  once (cell-priority map and 16 per-band text passes deleted) →
  shader-masked actors, matching original Sierra framebuffer order
  (`doc/text_and_picture_compositing_architecture.md` §1) and all
  three of its case studies (SQ2 rope text, PQ1 newspaper photo,
  SQ1 keypad banner). One documented divergence: a text cell
  straddling a priority boundary — flat order keeps text over the
  intruding higher-band scenery, as the original framebuffer did;
  slice order lets the intrusion overpaint. Keep this in mind when
  scoping "pixel-identical" goldens above to actor cases.
- **Fractional-scale sprite seams (field report, PQ2 doors at
  scales 2.32–2.75, DPR 2):** a plain shader `drawRect` gives edge
  device pixels partial (AA on) or zero (AA off, center exactly on
  the boundary) coverage, opening a 1px seam along sprite edges.
  Fixed by rasterizing a rect inflated by half a playfield pixel
  with AA off and letting the shader's floored playfield-pixel test
  (`floor(fragCoord + 1e-3)`) decide coverage — every device pixel
  then matches the naive spec oracle exactly at scales 3.25/5.5/6.5
  in the goldens ((f)–(h) cases). The Skia test backend never
  reproduced the original discard, so the Impeller field retest is
  the confirming evidence. One residual seam per scale remained at
  3.25–3.42 (field retest 2), at which point the shader was
  rewritten to continuous coordinates with hardware nearest
  selection (no `floor()` of fragCoord at all) plus a 1e-3
  tie-break: reproducing the mechanism in tests showed exact-tie
  fragment centers (e.g. scale 6.5 device px 6 → playfield 1.0)
  make nearest pick the lower texel — the blocking side of a
  priority step — discarding the sprite's first column, exactly the
  field symptom. Final confirmation on Impeller still pending.

---

## Suggested sequencing

- **Session 1:** rank 1 (test honesty + CI), then the small P0s in any
  order — 2, 3, 5, 7 are independent one-file fixes with obvious tests.
- **Session 2:** 4 + 12 together (typed decode errors are only useful
  once the interpreter loop survives them), then 13 and 6.
- **Session 3:** P1 remainder — 8, 9, 10, 11.
- **Then:** rank 14 spike (fragCoord mapping + equality edge + text
  decision) as its own throwaway-prototype session; migrate only if
  the spike passes the acceptance goldens against the slice path.

Worker agents for this plan run on the cheaper worker model
(`muse-ember-1.0`, configured by the maintainer) with the lead agent
monitoring: the lead reviews every worker diff, independently re-runs
the item's Verify test plus the scoped suite above, and does not check
the box on a worker's self-reported green.

## Unverified / not reviewed

- Pre-existing failures observed 2026-11-19 (not regressions; verified
  failing at untouched `84edcaf`): the `test/ui/game_screen_test.dart`
  AI-panel test trips over the real local-AI sidecar's pending timer
  (`LocalSidecarManager._waitForReady`) on a machine where local AI is
  installed — it needs test isolation for the sidecar; and
  `test/engine/kq4_unicorn_ride_test.dart` failed once under full-suite
  load in a clean copy but passes in isolation (flake, cause unknown).
  The new GitHub CI workflow has not yet run on GitHub (unpushed); on
  a runner without local AI installed the AI-panel test may pass, but
  that is unverified.
- Full AGI + SCI test-suite pass/fail totals (with game data present),
  coverage percentages, and `flutter pub outdated` / dependency audit
  were never run. A full run **without** game data (clean copy,
  2026-11-19) gave 742 passed / 198 skipped / the 2 pre-existing
  failures above.
- All items marked "suspected" (AGI LZW KwKwK prefix-walk hang,
  `lzw_decompression.dart:61`; `PriorityTable` base > 168; macOS sink
  pause-resume/flush behaviour; SCI `runVm` pop-and-break; cyclic
  superclass recursion; movement tunneling; keyboard bubbling from
  sidebar fields; SaveLoad double-confirm) are code-derived, not
  reproduced at runtime. Reproduce before fixing.
- Not reviewed at all: `lib/engine/ai/` (sidecar process spawn,
  embedding HTTP, disk caches — newest and most security-relevant
  code; give it its own review), `lib/sci/font/`, `lib/sci/cursor/`,
  `lib/ui/shaders/` (`.frag` source), native macOS/Windows runners
  and entitlements, SCI decompiler/disassembler bodies,
  `tool/bundle_llama_server.dart`.
- ~90 P2/P3 findings from the subsystem reviews were not individually
  re-verdicted by the adversarial pass (which covered 10 claims);
  treat next-tier items as strong leads, re-verified at fix time.
- No reference game was booted end-to-end and no audio was auditioned
  on hardware during the review; the early-SCI0 misdispatch magnitude
  (rank 6) is therefore code-derived.
