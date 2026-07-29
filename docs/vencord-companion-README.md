# Immaterial Impulse Discord Voice Vencord companion

Vesktop's built-in arRPC socket supports Rich Presence but not Discord's
authenticated voice RPC commands. This Vencord user plugin publishes the same
voice state locally so the Quickshell plugin can support Vesktop without
removing the regular Discord RPC backend.

## Quick install (Vesktop)

```
~/.config/quickshell/ii/scripts/discordVoice/install_companion.sh
```

The script clones/updates Vencord into
`~/.local/share/immaterial-impulse/Vencord`, drops the companion into
`src/userplugins/end4DiscordVoice`, builds with pnpm, and points Vesktop's
Vencord Location at the built `dist` (backing up `state.json` first — close
Vesktop fully before running). Then start Vesktop; **End4DiscordVoice** is
enabled by default and visible in Vencord's Plugins page. Re-run the script
any time to update. Needs `git`, `node` and `pnpm` (or corepack).

## Manual install

Install this directory as `src/userplugins/end4DiscordVoice` in a Vencord source
checkout, run `pnpm build`, copy the checkout's `package.json` into `dist/`,
select that `dist` directory under Vesktop Settings → Vencord Location, then
fully restart Vesktop.

## Other clients

Official Discord needs no companion — the shell uses Discord's native local
RPC. Legcord is not supported: it bundles its own Vencord build with no
custom-location picker, and the companion requires Vencord's native plugin
helpers (it opens a local Unix socket from the Electron main process).

The companion uses a user-only Unix socket at
`$XDG_RUNTIME_DIR/end4-discord-voice-vencord.sock`. Vencord Flux events push
voice state immediately, while mute/deafen commands return over the same
connection. The five-second heartbeat is only for crash detection and
reconnection; it does not poll Discord state. No Discord token is read or
exported.

Because the heartbeat is that infrequent, a Flux event arriving while a publish
is already in flight is re-published as soon as that one finishes rather than
dropped — otherwise the shell would show stale mute state for up to five
seconds. If `XDG_RUNTIME_DIR` is unset the companion disables itself; it never
falls back to a shared temporary directory.
