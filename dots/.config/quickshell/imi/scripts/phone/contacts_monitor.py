#!/usr/bin/env python3
"""Publish a phone's contacts from the vCards KDE Connect keeps on disk.

KDE Connect's contacts plugin does not answer "list the contacts" over D-Bus;
its job is to write one `.vcf` per contact into
`$XDG_DATA_HOME/kpeoplevcard/kdeconnect-<deviceId>/` for KPeople to read.
This script is the shell's KPeople: it resolves that directory (the named
device's, else the most recently modified `kdeconnect-*`), parses every card
and prints NDJSON on stdout:

    {"event": "ready", "sourcePath": "...", "count": N}
    {"event": "snapshot", "contacts": [...]}          only when the set changed
    {"event": "error", "code": "no_contact_source", "message": "..."}

A snapshot is published only when the SHA-256 of the parsed set moves, so the
watcher can re-read on every directory tick and cost the shell nothing while
nothing moved. With `--once` it prints one round and exits 0 whatever it found.
Without it, it watches: `gio monitor -d` on the directory when gio is on PATH
(a 250 ms debounce folds the burst one sync writes), a 3 s poll when it is not
or when gio dies, and the poll again while there is no source at all - the
directory appears on the first sync after pairing, and a watcher that exits on
"nothing there yet" is a watcher the shell's restart ladder gives up on.

The cards Android exports are vCard 2.1: names are QUOTED-PRINTABLE and
soft-wrapped with a trailing `=` continued on an UNINDENTED line (a plain
unfold truncates them), photos are base64 folded over indented lines, and a
raw contact that never had a name arrives with its number as FN and N (SIM
imports, call-blocker lists) - those are flagged `nameless` rather than
dropped, so the shell can hide them and still keep a starred one.
"""

import argparse
import base64
import binascii
import hashlib
import json
import os
import quopri
import re
import select
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

DEBOUNCE_SECONDS = 0.25
POLL_SECONDS = 3.0
# A gio that exits sooner than this after starting is not watching anything
# (no inotify, a directory it cannot read); the poll takes over rather than
# respawning it forever.
GIO_HEALTHY_SECONDS = 2.0

PHONE_TYPES = {"HOME": "home", "WORK": "work", "MAIN": "main", "OTHER": "other", "FAX": "fax"}
EMAIL_TYPES = {"HOME": "home", "WORK": "work"}
PHOTO_MIME = {"JPEG": "image/jpeg", "JPG": "image/jpeg", "PNG": "image/png",
              "GIF": "image/gif", "WEBP": "image/webp"}


def data_root():
    xdg = os.environ.get("XDG_DATA_HOME")
    base = Path(xdg) if xdg else Path.home() / ".local" / "share"
    return base / "kpeoplevcard"


def find_device_directory(root, device_id=None):
    if not root.is_dir():
        return None
    dirs = [d for d in root.iterdir() if d.is_dir() and d.name.startswith("kdeconnect-")]
    if not dirs:
        return None
    if device_id:
        for d in dirs:
            if d.name == f"kdeconnect-{device_id}":
                return d
        for d in dirs:
            if device_id in d.name:
                return d
    return max(dirs, key=lambda d: d.stat().st_mtime)


def unfold(text):
    """Logical lines: indented continuations joined (RFC 2425), and a
    QUOTED-PRINTABLE value whose line ends in `=` continued on the next line
    even though vCard 2.1 writes that continuation with no indent."""
    lines = []
    for physical in text.splitlines():
        if lines and physical[:1] in (" ", "\t"):
            lines[-1] += physical[1:]
        elif lines and lines[-1].endswith("=") and _is_quoted_printable(lines[-1]):
            lines[-1] = lines[-1][:-1] + physical
        else:
            lines.append(physical)
    return lines


def _is_quoted_printable(line):
    head = line.split(":", 1)[0].upper()
    return "QUOTED-PRINTABLE" in head


def parse_params(param_text):
    """`;CELL;PREF` / `;TYPE=CELL,VOICE` / `;ENCODING=b;TYPE=PNG` as one set of
    upper-cased tokens (every bare param, every key, every value in a list)
    plus the last value seen per key."""
    tokens, values = set(), {}
    for param in param_text.split(";"):
        if not param:
            continue
        if "=" in param:
            key, value = param.split("=", 1)
            tokens.add(key.upper())
            values[key.upper()] = value
            for item in value.split(","):
                tokens.add(item.upper())
        else:
            tokens.add(param.upper())
    return tokens, values


def unescape(value):
    value = value.replace("\\n", "\n").replace("\\N", "\n")
    value = value.replace("\\,", ",").replace("\\;", ";")
    return value.strip()


def decode_quoted_printable(value, charset):
    try:
        return quopri.decodestring(value.encode("ascii", errors="replace")).decode(charset, errors="replace")
    except (LookupError, ValueError):
        return quopri.decodestring(value.encode("ascii", errors="replace")).decode("utf-8", errors="replace")


def normalize_phone(value):
    return re.sub(r"[\s\-().]", "", value)


def looks_like_number(text):
    stripped = re.sub(r"[\s\-()./]", "", text)
    return bool(re.fullmatch(r"\+?\d+", stripped))


def _photo_data_uri(value, tokens, values):
    stripped = value.strip()
    if stripped.lower().startswith("data:"):
        return stripped
    inline = ("BASE64" in tokens or "B" in tokens
              or values.get("ENCODING", "").upper() in ("B", "BASE64"))
    if not inline:
        return ""
    clean = re.sub(r"\s+", "", stripped)
    try:
        base64.b64decode(clean, validate=True)
    except (ValueError, binascii.Error):
        return ""
    mime = ""
    for token in tokens:
        if token in PHOTO_MIME:
            mime = PHOTO_MIME[token]
    if not mime:
        declared = values.get("MEDIATYPE") or values.get("TYPE") or ""
        mime = declared.lower() if "/" in declared else PHOTO_MIME.get(declared.upper(), "image/jpeg")
    return f"data:{mime};base64,{clean}"


def parse_vcard(text, file_name, source_id):
    """One card's text as the contact record the shell reads, or None for a
    card that carries neither a name, a number nor an address."""
    fn = given = family = org = uid = kdeconnect_id = ""
    phones, emails = [], []
    photo = ""

    for line in unfold(text):
        if ":" not in line:
            continue
        head, value = line.split(":", 1)
        key, _, param_text = head.partition(";")
        key = key.upper()
        tokens, values = parse_params(param_text)
        if "QUOTED-PRINTABLE" in tokens or values.get("ENCODING", "").upper() == "QUOTED-PRINTABLE":
            value = decode_quoted_printable(value, values.get("CHARSET", "utf-8"))

        if key == "FN":
            fn = unescape(value)
        elif key == "N":
            parts = [unescape(part) for part in value.split(";")]
            family = parts[0] if parts else ""
            given = parts[1] if len(parts) > 1 else ""
        elif key == "ORG":
            org = unescape(value).strip(";")
        elif key == "UID":
            uid = value.strip()
        elif key.startswith("X-KDECONNECT-ID-DEV-"):
            kdeconnect_id = value.strip()
        elif key == "TEL":
            number = unescape(value)
            if number.lower().startswith("tel:"):
                number = number[4:].strip()
            if not number:
                continue
            kind = "mobile"
            if not tokens & {"CELL", "MOBILE"}:
                for token, name in PHONE_TYPES.items():
                    if token in tokens:
                        kind = name
                        break
            phones.append({
                "value": number,
                "normalized": normalize_phone(number),
                "type": kind,
                "primary": "PREF" in tokens,
            })
        elif key == "EMAIL":
            address = unescape(value)
            if not address:
                continue
            kind = "personal"
            for token, name in EMAIL_TYPES.items():
                if token in tokens:
                    kind = name
                    break
            emails.append({"value": address, "type": kind, "primary": "PREF" in tokens})
        elif key == "PHOTO":
            photo = _photo_data_uri(value, tokens, values) or photo

    phones = _dedupe(phones, lambda p: p["normalized"])
    emails = _dedupe(emails, lambda e: e["value"].lower())
    for entries in (phones, emails):
        if entries and not any(entry["primary"] for entry in entries):
            entries[0]["primary"] = True

    display_name = fn or f"{given} {family}".strip() or (phones[0]["value"] if phones else "")
    if not display_name and not emails:
        return None
    if not display_name:
        display_name = emails[0]["value"]

    nameless = not any(part and not looks_like_number(part) for part in (fn, given, family, org))

    if not uid:
        uid = kdeconnect_id
    if not uid:
        seed = f"{file_name}_{display_name}_{phones[0]['value'] if phones else ''}"
        uid = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]

    return {
        "id": uid,
        "displayName": display_name,
        "givenName": given,
        "familyName": family,
        "organization": org,
        "phones": phones,
        "emails": emails,
        "photo": photo,
        "nameless": nameless,
        "source": source_id,
    }


def _dedupe(entries, key):
    seen, kept = set(), []
    for entry in entries:
        marker = key(entry)
        if marker in seen:
            continue
        seen.add(marker)
        kept.append(entry)
    return kept


def parse_vcard_file(path, source_id):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    return parse_vcard(text, path.name, source_id)


def read_contacts(directory):
    contacts = []
    for path in sorted(directory.glob("*.vcf")):
        parsed = parse_vcard_file(path, directory.name)
        if parsed:
            contacts.append(parsed)
    contacts.sort(key=lambda c: c["displayName"].lower())
    return contacts


def emit(message):
    try:
        print(json.dumps(message), flush=True)
    except BrokenPipeError:
        # The shell that was reading went away; there is nobody to tell.
        os._exit(0)


class ContactMonitor:
    def __init__(self, device_id=None):
        self.device_id = device_id
        self.source = None
        self.last_hash = None
        self.missing_reported = False

    def update_and_emit(self):
        """Re-read the source and publish what changed. False when there is no
        source, reported once per stretch of absence."""
        directory = find_device_directory(data_root(), self.device_id)
        if directory is None:
            if not self.missing_reported:
                emit({"event": "error", "code": "no_contact_source",
                      "message": "No KDE Connect contacts directory under " + str(data_root())})
            self.missing_reported = True
            self.source = None
            self.last_hash = None
            return False

        self.missing_reported = False
        contacts = read_contacts(directory)
        payload = json.dumps(contacts, sort_keys=True)
        digest = hashlib.sha256(payload.encode("utf-8")).hexdigest()
        source = str(directory)
        if source != self.source or digest != self.last_hash:
            emit({"event": "ready", "sourcePath": source, "count": len(contacts)})
        if digest != self.last_hash:
            emit({"event": "snapshot", "contacts": contacts})
        self.source, self.last_hash = source, digest
        return True


def _die_with_parent():
    # PR_SET_PDEATHSIG: the gio child follows this process down even when
    # this process is killed outright and its `finally` never runs.
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def _sleep_unless_orphaned(seconds, parent):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if os.getppid() != parent:
            sys.exit(0)
        time.sleep(min(0.5, max(0.0, deadline - time.monotonic())))


def _watch_with_gio(monitor, gio, parent):
    """True while gio held the directory long enough to count as working;
    False when it died fast, so the caller stops asking it."""
    started = time.monotonic()
    proc = subprocess.Popen([gio, "monitor", "-d", monitor.source],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            preexec_fn=_die_with_parent)
    fd = proc.stdout.fileno()
    pending = False
    try:
        while True:
            ready, _, _ = select.select([fd], [], [], DEBOUNCE_SECONDS if pending else POLL_SECONDS)
            if os.getppid() != parent:
                sys.exit(0)
            if ready:
                if os.read(fd, 65536) == b"":
                    return time.monotonic() - started >= GIO_HEALTHY_SECONDS
                pending = True
                continue
            if pending:
                pending = False
                if not monitor.update_and_emit():
                    return True
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()


def watch(monitor):
    parent = os.getppid()
    gio = shutil.which("gio")
    while True:
        if not monitor.update_and_emit():
            _sleep_unless_orphaned(POLL_SECONDS, parent)
            continue
        if gio is None:
            _sleep_unless_orphaned(POLL_SECONDS, parent)
            continue
        if not _watch_with_gio(monitor, gio, parent):
            sys.stderr.write("gio monitor exited immediately; polling instead\n")
            gio = None


def main():
    parser = argparse.ArgumentParser(description="Publish a KDE Connect device's contacts as NDJSON")
    parser.add_argument("--device", help="KDE Connect device id whose kdeconnect-<id> directory to read")
    parser.add_argument("--once", action="store_true", help="print one round and exit")
    args = parser.parse_args()

    monitor = ContactMonitor(args.device)
    if args.once:
        monitor.update_and_emit()
        return 0
    watch(monitor)
    return 0


if __name__ == "__main__":
    sys.exit(main())
