/*
 * end4-pC Discord Voice companion for Vencord
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { IpcMainInvokeEvent } from "electron";
import { constants } from "fs";
import { readFile, rename, unlink, writeFile } from "fs/promises";
import { join } from "path";

// O_NOFOLLOW refuses a symlink planted at the path; O_TRUNC keeps a stale
// temporary file left by a crash from wedging every later publish.
const WRITE_FLAGS = constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | constants.O_NOFOLLOW;

// Confined to XDG_RUNTIME_DIR, which is user-owned and mode 0700. There is
// deliberately no fallback to a shared temporary directory: any local user
// could otherwise plant the state file or pre-create these paths as symlinks.
const runtime = process.env.XDG_RUNTIME_DIR || "";
const statePath = runtime ? join(runtime, "end4-discord-voice-vencord.json") : "";
const commandPath = runtime ? join(runtime, "end4-discord-voice-vencord.commands") : "";

export async function publishState(_: IpcMainInvokeEvent, json: string) {
    if (!statePath) return;
    const temporary = statePath + ".tmp";
    await writeFile(temporary, json, { encoding: "utf8", mode: 0o600, flag: WRITE_FLAGS });
    await rename(temporary, statePath);
}

export async function readCommands(_: IpcMainInvokeEvent): Promise<string> {
    if (!commandPath) return "";
    // Rename before reading so a command written between the read and the
    // truncate cannot be lost: the bridge recreates the file on its next write.
    const claimed = commandPath + ".claimed";
    try {
        await rename(commandPath, claimed);
    } catch (error: any) {
        if (error?.code === "ENOENT") return "";
        throw error;
    }
    try {
        return await readFile(claimed, "utf8");
    } finally {
        await unlink(claimed).catch(() => undefined);
    }
}
