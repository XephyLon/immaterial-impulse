# Proposal: voice input for the assistant

> Draft / tracking proposal. Not scheduled. Paths are relative to
> `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

Dictate a message to the assistant instead of typing it: hold a key (or press a
mic chip in the composer), speak, release, and the transcript lands in the
composer as an editable draft. Local transcription by default; a cloud
transcriber only when the user has already trusted that provider with a key.

## Current state

There is no speech-to-text anywhere in the shell. The pieces around it exist:

- **Microphone capture** has one working precedent:
  `scripts/musicRecognition/recognize-music.sh` picks the default source with
  `pactl` and feeds `songrec`; `services/SongRec.qml` drives it as a `Process`
  with a timeout and a "Listening..." state on the quick toggle
  (`modules/common/models/quickToggles/MusicRecognitionToggle.qml`).
- **The privacy indicator** (`services/MediaCapture.qml`) lights when any
  process opens the microphone. Dictation must light it too; that is the
  honest behaviour, not a bug to hide.
- **The composer** keeps a durable draft per session (`services/AiDrafts.qml`:
  `record(key, text)` / `take(key)`), so a transcript can be appended to
  whatever the user already typed without a new store.
- **The composer's chip rail** is `modules/imi/sidebarLeft/aiChat/ChatControlBar.qml`
  (`ControlChip`), where a mic chip belongs next to attach/model.
- **Provider credentials** live only in `services/KeyringStorage.qml`; the
  `ApiStrategy` subclasses under `services/ai/` already know how to talk to
  OpenAI, Gemini, Mistral and Anthropic with those keys.
- **IPC**: `services/Ai.qml` exposes an `IpcHandler { target: "ai" }`, so a
  Hyprland keybind can start and stop dictation without a new entry point.

The `ai-assistant-upgrade` proposal listed dictation as "a separate feature
with its own entry on the shortlist". This is that entry.

## Why

- Long prompts are the assistant's best use and the worst thing to type into a
  sidebar composer.
- A push-to-talk keybind makes the assistant reachable without opening the
  sidebar first, which is how people use phone assistants.
- Everything but the transcriber is already built; the feature is one script,
  one chip, and one config block.

## Approach

**1. The transcriber script** — `scripts/ai/ai_dictate.py`.

- `start`: records the default source with `pw-record` (PipeWire) to a temp
  WAV under the session's runtime dir; falls back to `parec`. Writes its pid
  so `stop` can find it.
- `stop`: ends the recording, transcribes, prints one JSON line
  `{"ok": true, "text": "...", "engine": "local", "seconds": 4.2}` or
  `{"ok": false, "error": "..."}`.
- Engines, chosen by `ai.dictation.engine`:
  - `local` (default): `faster-whisper` if importable, else the `whisper-cli`
    binary from `whisper.cpp`. Model size from `ai.dictation.model`
    (default `base`). The model file is downloaded **only** through an
    explicit "Download model" action in Settings, never on first use — the
    same rule the Wallpaper Engine prebuilt follows.
  - `provider`: OpenAI `/v1/audio/transcriptions` or Gemini audio input,
    through the same keyring-backed key the chat uses. Off unless chosen.
- No engine present: `{"ok": false, "error": "no transcriber"}`, and the mic
  chip shows the install hint instead of recording. The `PhoneDeps`-style
  probe (`services/PhoneDeps.qml`) is the model for "which optional dependency
  is missing and what installs it".

**2. The service** — `services/AiDictation.qml` (new singleton; needs a full
`qs` restart on first deploy).

- States: `idle` → `listening` → `transcribing` → `idle`. A watchdog caps a
  recording at `ai.dictation.maxSeconds` (default 60) so a stuck keybind does
  not record forever.
- On success: `AiDrafts.record(sessionKey, existingDraft + " " + text)`; the
  composer re-reads the draft. With `ai.dictation.autoSend` the text goes to
  `Ai.sendUserMessage` directly, but the default is edit-first.
- IPC: `ai.dictate("start")`, `ai.dictate("stop")`, `ai.dictate("toggle")`.
  `hypr/hyprland/keybinds.lua` gains a commented example binding.

**3. The UI.**

- A mic `ControlChip` in `ChatControlBar.qml`: press to start, press to stop;
  while listening it pulses and shows elapsed seconds; while transcribing it
  shows the spinner the send button already has.
- A one-line status ("Listening...", "Transcribing...", the error) in the
  composer's existing status slot; no new popup.
- Settings > AI: engine, model (with the download action and its size),
  auto-send, max seconds, keybind hint.

**4. Config** — under the existing `ai` block in `modules/common/Config.qml`:

```
property JsonObject dictation: JsonObject {
    property string engine: "local"      // local | provider
    property string model: "base"        // whisper model name
    property bool autoSend: false
    property int maxSeconds: 60
}
```

## Risks

- **Optional heavy dependency.** `faster-whisper` wants CTranslate2 and
  ideally CUDA; `whisper.cpp` wants a build. Both stay optional, probed, and
  installed by the user; the installer gains nothing mandatory.
- **Latency.** `base` on CPU transcribes 10 s of speech in roughly 2-4 s; the
  UI must show the transcribing state rather than look hung, and `tiny`
  should be offered for slow machines.
- **Privacy.** The provider engine sends audio off-machine. It is opt-in, the
  Settings row says where the audio goes, and the privacy indicator is red for
  the whole recording either way.
- **Keybind conflicts.** Push-to-talk wants a held key; Hyprland has no
  key-release dispatch, so "toggle" is the primitive and "hold" is a pair of
  `bind`/`bindr` entries the user adds knowingly.
- **Two microphones.** The phone-as-microphone feature (`services/PhoneMic.qml`)
  changes the default source while active; the script reads the default at
  `start`, which is the right answer, but the Settings row should say so.

## Open questions

- Default model: `base` (74 MB, decent English) or `small` (244 MB, better
  accents, slower)? Proposal says `base`, with `small` one click away.
- Should a transcript ever auto-send? Proposal says no by default; the option
  exists for the keybind-only flow.
- Language: auto-detect (whisper does this well) or follow the shell's
  `Translation` locale as a hint?

## Out of scope

- Wake-word / always-listening. That is a different privacy contract.
- Text-to-speech for replies.
- Streaming partial transcripts while speaking (whisper is batch; a streaming
  engine would be a second integration).
