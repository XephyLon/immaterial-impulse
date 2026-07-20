# end4-pC Discord Voice Vencord companion

Vesktop's built-in arRPC socket supports Rich Presence but not Discord's
authenticated voice RPC commands. This Vencord user plugin publishes the same
voice state locally so the Quickshell plugin can support Vesktop without
removing the regular Discord RPC backend.

Install this directory as `src/userplugins/end4DiscordVoice` in a Vencord source
checkout, run `pnpm build`, copy the checkout's `package.json` into `dist/`,
select that `dist` directory under Vesktop Settings → Vencord Location, then
fully restart Vesktop. **End4DiscordVoice** is enabled by default and remains
available in Vencord's Plugins page.

For the locally validated build, select:
`~/.local/share/end4-pC/Vencord/dist`.

The companion writes only current voice-channel display state to
`$XDG_RUNTIME_DIR/end4-discord-voice-vencord.json` with user-only permissions.
Mute/deafen requests use a separate user-only command file. No Discord token is
read or exported.

Official Discord does not need this companion. The Quickshell bridge continues
to use Discord's native local RPC and authorization flow when it is available.
