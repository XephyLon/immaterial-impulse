#!/usr/bin/env python3
"""Dictation for the assistant: record the default source, transcribe, print.

    ai_dictate.py probe                      what is available on this machine
    ai_dictate.py start                      begin recording (returns at once)
    ai_dictate.py stop [--engine local|provider] [--model base]
                                             end the recording and transcribe
    ai_dictate.py status
    ai_dictate.py download --model base      fetch a local model, explicitly

Recording is `pw-record` (PipeWire) or `parec`, 16 kHz mono, into the
runtime dir. Transcription is local by default: `faster-whisper` (in the
shell's uv venv or the system python) or a `whisper-cli` binary from
whisper.cpp with a ggml model; `provider` sends the audio to an
OpenAI-compatible transcription endpoint with the key the shell puts in
API_KEY. A model file is never downloaded on first use - `download` is the
only path, behind a Settings button.

Output is one JSON object, exit 0 either way. IMI_DICTATE_FAKE_TRANSCRIPT is
the test seam: `stop` skips transcription and returns that text, so the
state machine and the recorder can be driven without a model.
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import time

OPENAI_URL = "https://api.openai.com/v1/audio/transcriptions"


def runtime_dir():
    base = os.environ.get("IMI_DICTATE_RUNTIME_DIR") or os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    d = os.path.join(base, "imi-dictate")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def state_path():
    return os.path.join(runtime_dir(), "recording.json")


def read_state():
    try:
        with open(state_path()) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def venv_python():
    venv = os.environ.get("IMMATERIAL_IMPULSE_VIRTUAL_ENV") or os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") \
        or os.path.expanduser("~/.local/state/quickshell/.venv")
    py = os.path.join(venv, "bin", "python")
    return py if os.access(py, os.X_OK) else None


def python_with_faster_whisper():
    """The interpreter that can import faster_whisper: this one, or the venv's."""
    for py in (sys.executable, venv_python()):
        if not py:
            continue
        try:
            r = subprocess.run([py, "-c", "import faster_whisper"], capture_output=True, timeout=20)
            if r.returncode == 0:
                return py
        except (OSError, subprocess.TimeoutExpired):
            pass
    return None


def whisper_cpp_model(model):
    override = os.environ.get("IMI_WHISPER_CPP_MODEL")
    if override and os.path.isfile(override):
        return override
    p = os.path.expanduser(f"~/.cache/whisper.cpp/ggml-{model}.bin")
    return p if os.path.isfile(p) else None


def recorder():
    if shutil.which("pw-record"):
        return "pw-record"
    if shutil.which("parec"):
        return "parec"
    return None


def probe(model="base"):
    return {
        "ok": True,
        "recorder": recorder(),
        "faster_whisper": python_with_faster_whisper() is not None,
        "whisper_cli": shutil.which("whisper-cli"),
        "whisper_cpp_model": whisper_cpp_model(model),
        "venv": venv_python(),
    }


def start():
    st = read_state()
    if st and alive(st.get("pid", -1)):
        return {"ok": False, "error": "Already recording", "seconds": time.time() - st.get("started", time.time())}
    rec = recorder()
    if not rec:
        return {"ok": False, "error": "No recorder: install pipewire (pw-record) or pulseaudio-utils (parec)"}
    wav = os.path.join(runtime_dir(), f"take-{int(time.time() * 1000)}.wav")
    if rec == "pw-record":
        cmd = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", wav]
    else:
        cmd = ["parec", "--rate=16000", "--channels=1", "--format=s16le", "--file-format=wav", wav]
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    with open(state_path(), "w") as f:
        json.dump({"pid": proc.pid, "wav": wav, "started": time.time(), "recorder": rec}, f)
    return {"ok": True, "recording": True, "wav": wav, "recorder": rec}


def status():
    st = read_state()
    if st and alive(st.get("pid", -1)):
        return {"ok": True, "recording": True, "seconds": round(time.time() - st["started"], 1)}
    return {"ok": True, "recording": False, "seconds": 0}


def end_recording():
    st = read_state()
    if not st:
        return None, {"ok": False, "error": "Not recording"}
    pid = st.get("pid", -1)
    if alive(pid):
        try:
            os.kill(pid, signal.SIGINT)
        except OSError:
            pass
        deadline = time.time() + 3
        while alive(pid) and time.time() < deadline:
            time.sleep(0.05)
        if alive(pid):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
    try:
        os.remove(state_path())
    except OSError:
        pass
    st["seconds"] = round(time.time() - st.get("started", time.time()), 1)
    return st, None


def transcribe_local(wav, model):
    py = python_with_faster_whisper()
    if py:
        code = (
            "import sys, json\n"
            "from faster_whisper import WhisperModel\n"
            "m = WhisperModel(sys.argv[2], device='auto', compute_type='int8')\n"
            "segments, info = m.transcribe(sys.argv[1], vad_filter=True)\n"
            "print(json.dumps({'text': ' '.join(s.text.strip() for s in segments).strip(), 'language': info.language}))\n"
        )
        r = subprocess.run([py, "-c", code, wav, model], capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            raise RuntimeError((r.stderr or "faster-whisper failed").strip()[-400:])
        out = json.loads(r.stdout.strip().splitlines()[-1])
        return out["text"], "faster-whisper"
    cli = shutil.which("whisper-cli")
    ggml = whisper_cpp_model(model)
    if cli and ggml:
        r = subprocess.run([cli, "-m", ggml, "-f", wav, "-nt", "-np", "-l", "auto"], capture_output=True, text=True,
                           timeout=600)
        if r.returncode != 0:
            raise RuntimeError((r.stderr or "whisper-cli failed").strip()[-400:])
        return " ".join(line.strip() for line in r.stdout.splitlines() if line.strip()), "whisper.cpp"
    if cli and not ggml:
        raise RuntimeError(f"whisper-cli found but no model at ~/.cache/whisper.cpp/ggml-{model}.bin "
                           "(set IMI_WHISPER_CPP_MODEL or use Download model)")
    raise RuntimeError("No local transcriber: install faster-whisper into the shell's venv "
                       "(uv pip install faster-whisper) or whisper.cpp's whisper-cli")


def transcribe_provider(wav, model):
    key = os.environ.get("API_KEY", "")
    if not key:
        raise RuntimeError("No API key for the transcription provider")
    url = os.environ.get("IMI_DICTATE_PROVIDER_URL") or OPENAI_URL
    r = subprocess.run(["curl", "-sS", "-m", "120", "-X", "POST", url, "-H", "Authorization: Bearer " + key,
                        "-F", f"file=@{wav}", "-F", f"model={model or 'whisper-1'}", "-F", "response_format=json"],
                       capture_output=True, text=True, timeout=130)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or "curl failed").strip()[-400:])
    payload = json.loads(r.stdout)
    if "text" not in payload:
        raise RuntimeError(str(payload.get("error", payload))[:400])
    return payload["text"], "provider"


def stop(engine, model):
    st, err = end_recording()
    if err:
        return err
    wav = st.get("wav", "")
    try:
        fake = os.environ.get("IMI_DICTATE_FAKE_TRANSCRIPT")
        if fake is not None:
            text, used = fake, "fake"
        elif not os.path.isfile(wav) or os.path.getsize(wav) < 1000:
            return {"ok": False, "error": "Nothing was recorded (is the microphone muted?)", "seconds": st["seconds"]}
        elif engine == "provider":
            text, used = transcribe_provider(wav, model if model and model != "base" else "whisper-1")
        else:
            text, used = transcribe_local(wav, model or "base")
        return {"ok": True, "text": text.strip(), "engine": used, "seconds": st["seconds"]}
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as e:
        return {"ok": False, "error": str(e), "seconds": st["seconds"]}
    finally:
        try:
            os.remove(wav)
        except OSError:
            pass


def download(model):
    py = python_with_faster_whisper()
    if not py:
        return {"ok": False, "error": "faster-whisper is not installed; install it into the shell's venv first "
                                      "(uv pip install faster-whisper)"}
    code = ("import sys\nfrom faster_whisper import WhisperModel\n"
            "WhisperModel(sys.argv[1], device='cpu', compute_type='int8')\nprint('ok')\n")
    r = subprocess.run([py, "-c", code, model], capture_output=True, text=True, timeout=1800)
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr or "download failed").strip()[-400:]}
    return {"ok": True, "model": model}


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["probe", "start", "stop", "status", "download"])
    parser.add_argument("--engine", default="local")
    parser.add_argument("--model", default="base")
    args = parser.parse_args(argv)
    try:
        if args.action == "probe":
            result = probe(args.model)
        elif args.action == "start":
            result = start()
        elif args.action == "stop":
            result = stop(args.engine, args.model)
        elif args.action == "download":
            result = download(args.model)
        else:
            result = status()
    except (OSError, ValueError, RuntimeError) as e:
        result = {"ok": False, "error": str(e)}
    sys.stdout.write(json.dumps(result) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
