# Accounts: Google and Proton in the shell

Tracking proposal, implemented in stages on `feat/accounts-integration`.

## Why

The shell already has a calendar (day dots from ICS feeds, `list_events` for the
assistant), a to-do list (a local JSON file), a VPN toggle (whatever NetworkManager
knows) and a keyring. None of it knows the accounts most people actually live in.
The ask: Google (calendar, tasks, mail) and Proton (mail, VPN, password manager,
calendar) as first-class sources, through the surfaces that exist - the sidebar
calendar and to-do, the bar, the quick panels, the assistant's tools - not a new app.

## What exists, and is reused (see the map in the PR)

- `services/IcsCalendar.qml` merges ICS sources; consumers (`CalendarWidget`,
  `Ai.list_events`, the modes engine) read it. It gains one more input:
  `setExternalEvents(sourceId, events)`, so any account-backed calendar lands in
  the same list with a `calendar` field. Google's secret ICS address and Proton
  Calendar's share link already work through `calendar.ics.urls`; that key had no
  settings rows - it gets them (Accounts > Calendar feeds).
- `services/KeyringStorage.qml` holds ONE libsecret item with a JSON blob. Every
  account credential goes under its own top-level key there
  (`google.oauth`, later `proton.bridge`), never a second item.
- `services/Tailscale.qml` is the daemon-backed provider template (installed →
  available → pure parser → poll); `GoogleCloud.qml` the keyring + helper
  template.

## Google

User OAuth 2.0 (installed-app loopback flow with PKCE), with the user's OWN OAuth
client. Google requires a client per application and does not allow shipping a
desktop client secret in an open-source tree, so - like gcalcli - the user pastes a
client ID and secret from their Google Cloud console once (Settings > Accounts >
Google), presses Connect, signs in in the browser, and the refresh token lands in
the keyring. Scopes: `calendar.readonly`, `tasks`, `gmail.readonly`, `userinfo.email`.

- `scripts/accounts/google_oauth.py` (stdlib only): `authorize` opens the
  consent page, listens on a loopback port for the code, exchanges it and prints
  `{refresh_token, email}`; `refresh` prints `{access_token, expires_in}`. Secrets
  travel in environment variables, never argv. Endpoints are overridable through
  `IMI_GOOGLE_OAUTH_BASE` for the tests' fake server.
- `services/GoogleAccount.qml`: `connected`, `email`, `accessToken`; keeps the
  token fresh while any Google feature is on; `connect()` / `disconnect()`.
- `services/GoogleCalendar.qml`: the selected calendars' events for the next 14
  days (`events.list`, `singleEvents`, so recurrences are expanded server-side -
  the ICS parser does none) → `IcsCalendar.setExternalEvents("google:<calendar>")`.
- `services/GoogleTasks.qml`: task lists and open tasks; add / complete / delete
  write through. The to-do widget gains a source row (Local | Google) while
  connected; the local list is untouched.
- `services/Gmail.qml`: the inbox unread count (`labels/INBOX`). A bar widget
  (`mailIndicator`: envelope + badge, click opens the inbox) and a
  `list_mail`-free first stage - the assistant's mail tool is a later stage.
- Calls are `curl` with a bearer header, JSON parsed by pure `google_api.js`
  (tested). The API base is overridable (`IMI_GOOGLE_API_BASE`) so the runtime
  harness runs against `tests/fake_google_api.py`.

## Proton

- **VPN**: the official app (`proton-vpn-gtk-app`) keeps a session in the keyring
  and `python-proton-vpn-api-core` exposes it. `scripts/accounts/protonvpn_ctl.py
  status|connect [country]|disconnect|countries` drives that API with the app's
  own login (the shell never sees the Proton password);
  `services/ProtonVpn.qml` polls status and a quick toggle (both panel styles)
  connects to the fastest server / disconnects. Absent the package or a login the
  toggle hides (`installed` → `available`). The NetworkManager profile the app
  creates is still listed by `Vpn.qml`, so nothing regresses.
- **Calendar**: Proton Calendar has no public API; the share link is an ICS feed
  → Calendar feeds.
- **Mail**: Proton Mail speaks IMAP only through Proton Bridge (a paid-plan
  desktop app). Stage 2: `services/ProtonMail.qml` reads the unread count over
  IMAP on `127.0.0.1:1143` with the Bridge password stored under
  `proton.bridge` in the keyring; the same `mailIndicator` shows either account.
  Not in stage 1 (Bridge is not installed on the reference machine, so it cannot
  be verified end to end).
- **Password manager**: Proton Pass has no Linux API or CLI. Nothing is built
  on it; the settings page says so rather than offering a dead row.

## Non-goals

Two-way calendar writes; a mail reader; syncing the local to-do file into Google
(the two lists stay separate - a merge needs stable ids the local file lacks);
Google Drive/Photos; GNOME Online Accounts or KDE accounts as the credential
source (neither daemon is on the reference machine; the keyring blob is).

## Settings

A new page, Settings > Accounts (`id: "accounts"`): sections Google (client ID /
secret, Connect / Disconnect with the signed-in address, switches for calendar /
tasks / mail, refresh interval), Proton (VPN switch + status, notes on calendar
feeds and Bridge), Calendar feeds (the ICS URLs and files, add / remove).

## Tests

`tst_google_api.qml` (parsers, URLs), `test_google_oauth.py` (the helper against
a fake token endpoint), `test_accounts_contract.py` (wiring, keyring key, the
search index, no secret in argv), `test_accounts_runtime.py` +
`AccountsRuntimeTest.qml` (a nested shell against `tests/fake_google_api.py`:
events reach IcsCalendar, tasks round-trip, the unread count lands).
