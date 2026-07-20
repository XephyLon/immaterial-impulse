#!/usr/bin/env python3
"""Small stdio bridge between Quickshell and Discord's local RPC socket.

The bridge emits one JSON object per line and accepts the same format on stdin.
It uses only Python's standard library and never logs OAuth tokens.
"""

from __future__ import annotations

import asyncio
import json
import os
import struct
import sys
import urllib.request
import time
from pathlib import Path
from typing import Any

CLIENT_ID = "207646673902501888"  # Discord StreamKit public client
SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
TOKEN_URL = "https://streamkit.discord.com/overlay/token"
AUTHORIZATION_TIMEOUT = 12.0
OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = range(5)


def emit(kind: str, **data: Any) -> None:
    print(json.dumps({"type": kind, **data}, separators=(",", ":")), flush=True)


class Bridge:
    def __init__(self) -> None:
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.nonce = 0
        self.pending: dict[str, str] = {}
        self.users: dict[str, dict[str, Any]] = {}
        self.channel: dict[str, Any] | None = None
        self.settings = {"mute": False, "deaf": False}
        self.current_path = ""
        self.authorization_failed_paths: set[str] = set()
        self.authorization_tasks: dict[str, asyncio.Task[None]] = {}
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        self.token_path = cache / "end4-pC" / "discord-voice-token.json"
        # The companion channel is deliberately confined to XDG_RUNTIME_DIR,
        # which is user-owned and mode 0700. Falling back to a shared directory
        # would let any local user plant the state file (fabricating
        # participants, and tearing down a live official-Discord session as a
        # side effect) or pre-create the command path as a symlink.
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        self.vencord_state_path = Path(runtime) / "end4-discord-voice-vencord.json" if runtime else None
        self.vencord_command_path = Path(runtime) / "end4-discord-voice-vencord.commands" if runtime else None
        self.vencord_active = False
        self.vencord_signature = ""

    def token(self) -> str:
        try:
            os.chmod(self.token_path, 0o600)
            return json.loads(self.token_path.read_text())["access_token"]
        except (OSError, KeyError, json.JSONDecodeError):
            return ""

    def save_token(self, token: str) -> None:
        self.token_path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.token_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"access_token": token}, handle)

    def clear_token(self) -> None:
        try:
            self.token_path.unlink()
        except FileNotFoundError:
            pass

    def next_nonce(self) -> str:
        self.nonce += 1
        return str(self.nonce)

    async def send(self, payload: dict[str, Any], opcode: int = OP_FRAME) -> None:
        if not self.writer:
            return
        body = json.dumps(payload).encode()
        self.writer.write(struct.pack("<II", opcode, len(body)) + body)
        await self.writer.drain()

    async def command(self, name: str, args: dict[str, Any] | None = None) -> None:
        nonce = self.next_nonce()
        self.pending[nonce] = name
        payload: dict[str, Any] = {"cmd": name, "nonce": nonce}
        if args is not None:
            payload["args"] = args
        await self.send(payload)

    async def subscribe(self, event: str, channel_id: str = "") -> None:
        nonce = self.next_nonce()
        self.pending[nonce] = "SUB_" + event
        payload: dict[str, Any] = {"cmd": "SUBSCRIBE", "evt": event, "nonce": nonce}
        if channel_id:
            payload["args"] = {"channel_id": channel_id}
        await self.send(payload)

    @staticmethod
    def candidate_paths() -> list[str]:
        runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        roots = [runtime, f"{runtime}/app/com.discordapp.Discord", "/tmp"]
        return [f"{root}/discord-ipc-{index}" for root in roots for index in range(10)]

    async def connect(self) -> bool:
        vencord_state = self.read_vencord_state()
        if vencord_state:
            self.apply_vencord_state(vencord_state, force=True)
            return True
        if self.writer and not self.writer.is_closing():
            return True
        for path in self.candidate_paths():
            if path in self.authorization_failed_paths or not os.path.exists(path):
                continue
            try:
                reader, writer = await asyncio.open_unix_connection(path)
                self.reader, self.writer, self.current_path = reader, writer, path
                await self.send({"v": 1, "client_id": CLIENT_ID}, OP_HANDSHAKE)
                opcode, ready = await self.receive(reader)
                if opcode == OP_CLOSE or ready.get("evt") != "READY":
                    raise ConnectionError("Discord rejected RPC handshake")
                emit("backend", backend="discord")
                emit("connected", socket=path)
                asyncio.create_task(self.read_loop(reader, writer))
                token = self.token()
                if token:
                    await self.authenticate(token)
                else:
                    emit("auth_required")
                return True
            except (OSError, ConnectionError, asyncio.IncompleteReadError):
                self.close()
        emit("unavailable", message="Discord is not running or RPC is unavailable")
        return False

    def read_vencord_state(self) -> dict[str, Any] | None:
        if self.vencord_state_path is None:
            return None
        try:
            # O_NOFOLLOW: never traverse a symlink planted at this path.
            descriptor = os.open(self.vencord_state_path, os.O_RDONLY | os.O_NOFOLLOW)
            with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
                data = json.loads(handle.read())
            if data.get("version") != 1 or data.get("backend") != "vencord":
                return None
            timestamp = float(data.get("timestamp", 0)) / 1000
            # Absolute difference: a clock-skewed or forged future timestamp
            # must expire too, or it would pin the bridge to a dead companion.
            if abs(time.time() - timestamp) > 4:
                return None
            return data
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return None

    def apply_vencord_state(self, data: dict[str, Any], force: bool = False) -> None:
        stable = {key: value for key, value in data.items() if key != "timestamp"}
        signature = json.dumps(stable, sort_keys=True, separators=(",", ":"))
        if not force and signature == self.vencord_signature:
            return
        if self.writer:
            self.close()
        for task in self.authorization_tasks.values():
            task.cancel()
        self.authorization_tasks.clear()
        self.pending.clear()
        self.vencord_active = True
        self.vencord_signature = signature
        emit("backend", backend="vencord")
        emit("authenticated", user=data.get("user") or {})
        emit("voice_channel", channel=data.get("channel"), users=data.get("users") or [])
        emit("voice_settings", mute=bool(data.get("mute")), deaf=bool(data.get("deaf")))

    async def vencord_monitor(self) -> None:
        while True:
            state = self.read_vencord_state()
            if state:
                self.apply_vencord_state(state)
            elif self.vencord_active:
                self.vencord_active = False
                self.vencord_signature = ""
                emit("disconnected", reason="Vesktop companion stopped")
                await self.connect()
            await asyncio.sleep(0.5)

    def send_vencord_command(self, **command: bool) -> None:
        if self.vencord_command_path is None:
            return
        line = json.dumps(command, separators=(",", ":")) + "\n"
        # O_NOFOLLOW keeps a symlink planted at this path from redirecting the
        # write; the creation mode covers permissions, so there is no chmod
        # afterwards that could be aimed at someone else's file.
        fd = os.open(self.vencord_command_path,
                     os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as handle:
            handle.write(line)

    def close(self) -> None:
        if self.writer:
            self.writer.close()
        self.reader = None
        self.writer = None
        self.current_path = ""

    async def receive(self, reader: asyncio.StreamReader | None = None) -> tuple[int, dict[str, Any]]:
        source = reader or self.reader
        assert source
        header = await source.readexactly(8)
        opcode, length = struct.unpack("<II", header)
        body = await source.readexactly(length)
        return opcode, json.loads(body.decode())

    async def authenticate(self, token: str) -> None:
        nonce = self.next_nonce()
        self.pending[nonce] = "AUTHENTICATE"
        await self.send({"cmd": "AUTHENTICATE", "args": {"access_token": token}, "nonce": nonce})

    async def authorize(self) -> None:
        state = self.read_vencord_state()
        if state:
            self.apply_vencord_state(state, force=True)
            return
        if not await self.connect():
            return
        emit("authorizing")
        nonce = self.next_nonce()
        self.pending[nonce] = "AUTHORIZE"
        await self.send({"cmd": "AUTHORIZE", "args": {
            "client_id": CLIENT_ID, "scopes": SCOPES, "prompt": "none"
        }, "nonce": nonce})
        self.authorization_tasks[nonce] = asyncio.create_task(
            self.authorization_timeout(nonce, self.current_path))

    def cancel_authorization_timeout(self, nonce: str) -> None:
        task = self.authorization_tasks.pop(nonce, None)
        if task and task is not asyncio.current_task():
            task.cancel()

    async def authorization_timeout(self, nonce: str, path: str) -> None:
        await asyncio.sleep(AUTHORIZATION_TIMEOUT)
        await self.handle_authorization_timeout(nonce, path)

    async def handle_authorization_timeout(self, nonce: str, path: str) -> None:
        if self.pending.pop(nonce, None) != "AUTHORIZE":
            return
        self.authorization_tasks.pop(nonce, None)
        self.authorization_failed_paths.add(path)
        # Some RPC-compatible clients only implement Rich Presence and silently
        # ignore voice authorization. Move on to another Discord socket instead
        # of leaving the connection and nonce wedged forever.
        self.close()
        if await self.connect():
            await self.authorize()
        else:
            emit("error", message=(
                "The connected Discord client does not support voice authorization. "
                "Vesktop/Vencord users must install and enable the end4 Discord Voice companion."))

    @staticmethod
    def exchange(code: str) -> str:
        request = urllib.request.Request(TOKEN_URL,
            data=json.dumps({"code": code}).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "end4-pC/DiscordVoice"},
            method="POST")
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode())["access_token"]

    async def read_loop(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            while not writer.is_closing():
                opcode, payload = await self.receive(reader)
                if opcode == OP_PING:
                    await self.send(payload, OP_PONG)
                elif opcode == OP_CLOSE:
                    break
                elif opcode == OP_FRAME:
                    await self.handle(payload)
        except (OSError, asyncio.IncompleteReadError, json.JSONDecodeError):
            pass
        if self.writer is writer:
            self.close()
            self.users.clear()
            self.channel = None
            emit("disconnected")

    async def handle(self, payload: dict[str, Any]) -> None:
        nonce = payload.get("nonce", "")
        event = payload.get("evt", "")
        if event == "ERROR":
            command = self.pending.pop(nonce, "")
            self.cancel_authorization_timeout(nonce)
            if command == "AUTHENTICATE":
                self.clear_token()
                emit("auth_required")
            else:
                emit("error", message=payload.get("data", {}).get("message", "Discord RPC error"))
            return
        if nonce in self.pending:
            self.cancel_authorization_timeout(nonce)
            await self.response(self.pending.pop(nonce), payload.get("data", {}))
            return
        if payload.get("cmd") == "DISPATCH":
            await self.dispatch(event, payload.get("data", {}))

    async def response(self, command: str, data: dict[str, Any]) -> None:
        if command == "AUTHORIZE":
            code = data.get("code", "")
            if not code:
                emit("error", message="Discord authorization was not completed")
                return
            try:
                token = await asyncio.to_thread(self.exchange, code)
                self.save_token(token)
                await self.authenticate(token)
            except Exception:
                emit("error", message="Discord token exchange failed")
        elif command == "AUTHENTICATE":
            emit("authenticated", user=data.get("user", {}))
            await self.subscribe("VOICE_CHANNEL_SELECT")
            await self.subscribe("VOICE_SETTINGS_UPDATE")
            await self.command("GET_SELECTED_VOICE_CHANNEL")
        elif command == "GET_SELECTED_VOICE_CHANNEL":
            await self.select_channel(data if data.get("id") else None)
        elif command in ("GET_VOICE_SETTINGS", "SET_VOICE_SETTINGS"):
            self.settings = {"mute": bool(data.get("mute")), "deaf": bool(data.get("deaf"))}
            emit("voice_settings", **self.settings)

    @staticmethod
    def voice_user(data: dict[str, Any]) -> dict[str, Any]:
        user, voice = data.get("user", {}), data.get("voice_state", {})
        return {"id": user.get("id", ""), "username": user.get("username", ""),
            "nick": data.get("nick") or user.get("global_name") or user.get("username", ""),
            "avatar": user.get("avatar", ""), "mute": bool(voice.get("mute") or voice.get("self_mute")),
            "deaf": bool(voice.get("deaf") or voice.get("self_deaf")), "speaking": False}

    async def select_channel(self, data: dict[str, Any] | None) -> None:
        self.users.clear()
        if not data:
            self.channel = None
            emit("voice_channel", channel=None, users=[])
            return
        self.channel = {"id": data.get("id", ""), "name": data.get("name", "Voice channel"),
                        "guild_id": data.get("guild_id", "")}
        for state in data.get("voice_states", []):
            participant = self.voice_user(state)
            if participant["id"]:
                self.users[participant["id"]] = participant
        emit("voice_channel", channel=self.channel, users=list(self.users.values()))
        for event in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE",
                      "SPEAKING_START", "SPEAKING_STOP"):
            await self.subscribe(event, self.channel["id"])
        await self.command("GET_VOICE_SETTINGS")

    async def dispatch(self, event: str, data: dict[str, Any]) -> None:
        if event == "VOICE_CHANNEL_SELECT":
            await self.command("GET_SELECTED_VOICE_CHANNEL")
        elif event in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE"):
            participant = self.voice_user(data)
            old = self.users.get(participant["id"], {})
            participant["speaking"] = old.get("speaking", False)
            if participant["id"]:
                self.users[participant["id"]] = participant
            emit("voice_state", users=list(self.users.values()))
        elif event == "VOICE_STATE_DELETE":
            self.users.pop(data.get("user", {}).get("id", ""), None)
            emit("voice_state", users=list(self.users.values()))
        elif event in ("SPEAKING_START", "SPEAKING_STOP"):
            uid = data.get("user_id", "")
            if uid in self.users:
                self.users[uid]["speaking"] = event == "SPEAKING_START"
            emit("voice_state", users=list(self.users.values()))
        elif event == "VOICE_SETTINGS_UPDATE":
            self.settings = {"mute": bool(data.get("mute")), "deaf": bool(data.get("deaf"))}
            emit("voice_settings", **self.settings)

    async def input_loop(self) -> None:
        loop = asyncio.get_running_loop()
        while True:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                return
            try:
                message = json.loads(line)
                command = message.get("cmd")
                if command == "connect":
                    await self.connect()
                elif command == "authorize":
                    await self.authorize()
                elif command == "set_voice_settings":
                    args = {key: bool(message[key]) for key in ("mute", "deaf") if key in message}
                    if self.vencord_active:
                        self.send_vencord_command(**args)
                    elif self.writer:
                        await self.command("SET_VOICE_SETTINGS", args)
                elif command == "disconnect":
                    self.close()
            except (json.JSONDecodeError, OSError):
                emit("error", message="Invalid bridge command")


async def main() -> None:
    bridge = Bridge()
    emit("ready")
    monitor = asyncio.create_task(bridge.vencord_monitor())
    await bridge.input_loop()
    monitor.cancel()
    bridge.close()


if __name__ == "__main__":
    asyncio.run(main())
