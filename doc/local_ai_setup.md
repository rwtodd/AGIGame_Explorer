# Local AI Setup (EmbeddingGemma 2 sidecar)

Command assist uses **on-device embeddings**. There is no API key, no account,
and no network traffic after a one-time model download. The app runs a local
`llama-server` (llama.cpp) serving the text-only EmbeddingGemma 2 encoder
(`embeddinggemma-2-Q8_0.gguf`, ~270M params, 768-dim vectors).

## How it looks to the player

1. Toggle **Enable Local AI Assist** on (sidebar or A/V settings → AI tab).
2. First use downloads the model once (~300 MB) with a progress indicator,
   then starts the server. Later uses are instant.
3. If anything fails, commands fall back to the native Sierra parser and the
   settings screen shows the reason. The **TEST** button re-checks the server.

Nobody ever starts, stops, or configures a server by hand.

## Server lifecycle (for developers)

`LocalSidecarManager` (`lib/engine/ai/local_sidecar_manager.dart`) owns this:

- **Adopt before spawn.** If `127.0.0.1:<port>` already serves 768-dim
  embeddings (e.g. the user's own `llama-server`), it is reused and **never**
  shut down by the app.
- **Spawn when needed.** Otherwise the app launches its bundled `llama-server`
  with `--model <weights> --port <port> --embeddings`.
- **Kill only what it spawned.** Engine `dispose()` (and explicit shutdown)
  terminates owned servers; adopted ones are left running.
- **Crash safety.** An owned server records `local_ai_server.json`
  (`{pid, port}`) in the config dir. A stale file is adopted when its port is
  healthy, discarded when not. Nothing is ever killed by PID, so a recycled
  PID can never cause the app to kill an unrelated process.
- **Port conflicts.** If the preferred port (default 8080) answers with
  incompatible vectors, the app binds a free loopback port instead.

Manual override: advanced users may set any OpenAI-compatible
`/v1/embeddings` endpoint in the settings field (e.g. their own server or
Ollama once it packages EmbeddingGemma 2).

## Weights

- Repo: `ggml-org/embeddinggemma-2-GGUF`, file `embeddinggemma-2-Q8_0.gguf`
  (text-only; the `mmproj-*` vision files are intentionally skipped).
- Stored under `<configDir>/models/` (`~/.config/flutter_agigame/models/`
  on macOS/Linux, `%APPDATA%/flutter_agigame/models/` on Windows).
- Old `ai_cache/gemini-embedding-001/` directories from the cloud era are
  orphaned, never read (caches are segregated by model slug).

## Bundling `llama-server` for release builds

Under the macOS app sandbox a binary downloaded at runtime cannot be
executed, so release builds bundle the server:

```sh
dart tool/fetch_llama_server.dart            # -> third_party/llama-server/
```

- **macOS:** copy `third_party/llama-server/macos-arm64/llama-server` into
  `MyApp.app/Contents/Resources/` and re-sign with the helper entitlements:
  ```sh
  codesign -s "<identity>" --entitlements macos/Runner/llama-server.entitlements \
    MyApp.app/Contents/Resources/llama-server
  ```
  (`com.apple.security.inherit` lets the sandboxed app execute its own helper.)
- **Windows:** place `third_party/llama-server/windows-x64/llama-server.exe`
  next to the built app `.exe`.
- **Dev fallback:** with no bundled binary, the app uses `llama-server` from
  `PATH` (`brew install llama.cpp` / `winget install llama.cpp`).

## Verifying against a real server

```sh
# one-time weights fetch is done by the app; for a manual check:
llama-server -m ~/.config/flutter_agigame/models/embeddinggemma-2-Q8_0.gguf \
  --port 8080 --embeddings
curl http://127.0.0.1:8080/v1/embeddings \
  -d '{"model":"embeddinggemma-2-text","input":["take key"]}'
```

Then enable AI Assist in the app: with a server already on 8080 it will be
adopted (`ownsServer == false`), and shutting the app down leaves it running.

**Version requirement (verified Oct 2026):** the server binary must know the
`gemma-embedding2` architecture. The Homebrew build installed on this machine
(`llama.cpp 7880`) predates it and fails with
`unknown model architecture: 'gemma-embedding2'` — use a newer llama.cpp
(`brew upgrade llama.cpp`, or `brew install --HEAD llama.cpp` to build master
immediately at the cost of a ~10–20 min compile, or `tool/fetch_llama_server.dart`,
then re-test).
The weights URL above was verified live (`embeddinggemma-2-Q8_0.gguf`,
~310 MB).

**Threshold validation (measured Oct 2026, real vectors):** the default 0.75
cosine threshold cleanly separates paraphrases from unrelated inputs on game
phrases — `grab key→take key` 0.894, `pick up the card→take card` 0.903,
`examine the monitor→look screen` 0.824, `look at the ogre→look ogre` 0.885,
vs `sing song` 0.695 and `talk to the alien` 0.710 (correctly rejected).
Note unrelated short phrases score ~0.70 rather than ~0, so the reject-side
margin is thin; keep 0.75 unless wider sampling says otherwise.
