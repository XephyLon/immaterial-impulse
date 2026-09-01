# Changelog

All notable changes to Immaterial Impulse are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/), and the project follows
[Semantic Versioning](https://semver.org/) (currently pre-1.0: `0.x` may make
breaking changes on a minor bump).

The version is stored in `VERSION` (a symlink to the shell's
`dots/.config/quickshell/imi/VERSION`, so it deploys with the config and the
About page can read it). The companion `qs-wallpaperengine` is versioned in its
own repo; the installer pins which revision it builds.

## [Unreleased]

### Changed
- **1x1 media widget icons are filled**, not outlined, so they read over the bare cover artwork.

## [1.0.0-rc-4] — 2026-09-01

### Fixed
- **Space Grotesk is optional now.** It was a hard font dependency of the
  install, so where that package is unreachable (some regions) the whole
  install failed. It is only the Expressive display font - the shell falls
  back without it, and it stays settable in Settings > Appearance.
- **Glassy line-level lyrics shimmer again.** BetterLyrics renders line-synced
  lyrics as word spans with fake ~0.05s-apart times and no per-word duration;
  the shell took them for real karaoke and raced the sweep to the last word (or
  never ran it). A line with no real per-word duration is now treated as
  line-level, so the sweep walks the whole line - the read LyricsPlus gives.

### Changed
- **Lyrics text is a notch larger** in the media view.

## [1.0.0-rc-3] — 2026-09-01

### Fixed
- **Glassy lyrics no longer pin at the top when the sidebar opens as a song
  starts.** BetterLyrics renders its line elements a beat before it fills
  their timestamps (each starts at data-time 0), and the reader accepted that
  half-rendered snapshot - stamping a whole block of lines at 0:00, so the
  highlight stuck there while the song played on (a play/pause forced a clean
  re-render). The reader now waits for real, increasing stamps before it
  accepts the DOM.
- **The media sidebar re-tints from each song's cover, live.** The card's
  cover-derived tint had its colour binding destroyed by an imperative write
  on the no-art path, so it only picked up colours at startup and never
  followed a track change. The binding is restored (it falls back to the
  theme when there is no art), and the player-selector dropdown is now
  transparent so it sits on the tint rather than a filled pill.

## [1.0.0-rc-2] — 2026-09-01

### Fixed
- **Glassy lyrics stop losing the async-render race.** When Glassy is the
  app playing a track, its BetterLyrics DOM renders a beat after the track
  changes; the shell's fetch used to give up after a fixed 3s and hand the
  song to a fallback provider that never got replaced. The Glassy reader now
  reads Glassy's own player bar: if it shows the current track it waits out
  the render (so the word-synced lines win), and if it shows a different one
  it bails immediately so playback Glassy does not own is not stalled.
- **No instrumental fillers for lyrics without per-word timing.** The
  breathing-note fillers between lines are emitted only after a word-timed
  line, whose sung-end is a real stamp; a line-level source (or a line-level
  line inside a mixed one) no longer guesses an instrumental break where
  there is none.
- **Lyrics sync survives opening the sidebar mid-song.** The word-sweep
  clock re-anchors on every track change, so starting a song and opening the
  media sidebar immediately no longer runs the new track's lines far ahead
  (interpolated from the previous song's stale position) until a play/pause
  forced a fresh poll.
- **The AI chat's generated-image tooltip tracks the pointer.** "Click to
  view fullscreen" sat on a bare container with no hover state, which the
  tooltip reads as always-on, so it hung on screen - even outside the
  sidebar - until a click. The image now carries a real hover flag, so the
  tooltip shows on hover and clears on leave.

## [1.0.0-rc-1] — 2026-09-01

### Added
- **Lyrics track the word, in both views.** The desktop media widget now
  shares the sidebar's word-synced lyrics view instead of its own line-
  level one, so the two stay in step. App-independent word sync through
  LyricsPlus/KPoe with a GlassyMusic DOM path that wins the async-render
  race, a small source indicator, romanization and translation toggles,
  right-to-left word order, and a fixed-speed sweep for lines that carry
  no per-word timing.
- **The media widget's two faces morph.** Switching the 3x2 between its
  controls and its lyrics travels one vertical axis - the transport,
  seeker and time lift and fade as the lyrics rise into place, no snap -
  and the lyrics toggle's glyph morphs its shape (cookie to clover) and
  its colour on the same clock rather than jumping.
- **Browse is every provider now.** The browse view leads with your own
  providers' models - each named "Provider: Model" and carrying a
  show/hide toggle that curates what the picker surfaces - followed by
  the OpenRouter index, one search across both. An empty curation
  surfaces everything, so small providers need no ceremony.
- **Browse OpenRouter, import with one click.** The picker's "Browse
  models…" row (and a door in Providers & keys) opens a searchable index
  of OpenRouter's catalogue - context, pricing, reasoning and vision at
  a glance. A click imports the model, keys it to your OpenRouter key,
  and selects it. Models now carry capability metadata; reasoning is
  requested wherever a model declares it.
- **Drafts survive.** The composer's unsent text persists per chat -
  and for the chat you haven't started yet - through restarts and
  session switches, restored whenever the composer is empty.
- **The composer remembers, and questions get second drafts.** Up/Down
  steps through this chat's past prompts shell-style (your unsent draft
  survives the round trip), and any question can be taken back - the
  edit_note action on the message, or Ctrl+Up for the last one -
  reworded, and resent as a fresh chat; the old branch stays in Chats.
  Ctrl+R redoes the last answer.
- **Chats save themselves.** Every conversation persists as a session
  the moment you send the first message - no /save needed. The tools
  bar's new history chip opens the list: pinned first, open on the row,
  rename in place, pin and delete on hover, and your old /save files
  waiting at the foot to be imported. /save now names the current
  session; /load imports the file it names.
- **The Intelligence tab reads as an instrument.** Three surfaces - a
  chip tools bar (model, temperature, key, tokens, new chat), the chat
  area, the composer - with an opening choreography: the pane waves in,
  the composer rises last through a de-blur, and reopening a
  conversation staggers the visible messages back onto the stage. The
  empty state greets you with a rolled hello (pin one with
  sidebar.ai.greeting) over a keycap rail of the keys worth knowing.
- **The Bar layout section is a draggable list.** The chip flows become
  grouped rows - drag handle, icon, name, remove - that lift on hold and
  part live as you drag, including across Left/Center/Right. Adding a
  widget is a dropdown and an Add button at each group's foot.
- **The quick toggles take pages.** The android grid becomes swipeable
  pages with a dot rail - compose each page deliberately in edit mode,
  add one with the + beside the dots, and empty pages sweep themselves
  away when editing ends. A dragged tile held against the pager's edge
  walks onto the neighbouring page. Existing layouts carry over as
  page one.
- **Apply a preset selectively.** Apply opens a dialog: six groups -
  wallpaper, theming, fonts, panels, widgets, everything else - all
  preselected so Enter still applies the whole preset, each showing how
  many sections the preset holds. App launch commands sit apart and are
  never preselected: a preset's apps.* strings are shell-executed, and
  with online presets planned they only ever apply when deliberately
  ticked.
- **The currency widget takes a 3x2: a month of real closes.** The
  maintainer's design grown from the 3x1: the hero corner holds still,
  the base gains its full name and a filled 30-day chart beneath, and
  every quote carries its own 7-day trend chart in the direction's
  colour. The trends are fetched truth, not decoration: the rates
  dataset publishes one snapshot per day, so the service walks the last
  month's dated files - politely, one file per step, ~30 cached CDN hits
  once and then one new file a day, persisted with the rest - and the
  charts stay on their honest flat placeholder until two closes exist.
- **The currency widget takes a 3x1, with a real day behind it.** The
  maintainer's design: the base currency as a hero block - Rates, the
  giant code, its flag, the payments chip - beside all four quotes in a
  two-column grid, each with which way the day went (arrow, percent,
  absolute), dividers between the columns and a "Last updated" stamp.
  The chart line is dynamic now: the rates API is a daily dataset, so
  the shell keeps its own 24-hour ring of the hourly refreshes (persisted
  across restarts) and the line, the arrows and the deltas all read what
  this machine actually observed. Until two samples exist the line keeps
  its old decorative curve and the movement columns stay quiet.
- **The world clock hands its size to the shell.** Its corner toggle is
  gone; the resize grip, the Settings size row and the edit-menu stepper
  walk its two shapes (the card, the row of dials), and a size chosen
  with the old toggle carries over.
- **The calendar takes a 3x2: today as a hero column beside the month.**
  An icon in its Material shape, the month in small caps, the weekday and
  the big date on the left; the whole month on its own surface to the
  right, with today circled, and the month steppers at the column's foot
  (the same travelling pair the 2x2 title row has). Every purpose is one element across all four sizes - the
  month text rewrites its spelling (AUG, August 2026, AUGUST) while it
  travels rather than being replaced by a twin, and the big date is the
  same element at 1x1 and 3x2, fading out over today's own circled cell
  in between. The calendar also hands its size to the shell with this:
  the two corner handles are gone, and the resize grip, the Settings size
  row and the edit-menu stepper - the same three faces every resizable
  widget has - walk its four sizes. A size chosen with the old handles
  carries over.
- **A GPU Monitor widget: GPU, VRAM, and swap.** The system monitor's
  missing metrics, as their own placeable widget - the host places one
  instance per plugin, so a separate package is what lets the graphics row
  sit beside the original three (or replace them). Same cards, same
  liquid-shape gauges, palette cycling the same three roles; the numbers
  come from the shell's existing resource service.
- **The media widget takes a 1x1.** Cover art fills the tile and a small
  transport row rides low across it - previous and next on discs, play on
  the same scalloped cookie the other sizes morph through. No seek ring,
  no time, no lyrics at this size; the resize grip walks to it after 2x1.
- **The Custom Image widget plays GIFs and can drop its backing.** A
  dropped .gif animates instead of freezing on its first frame, and a new
  "Transparent background" option removes the container colour behind the
  image, so a PNG's alpha shows the wallpaper through the shape.
- **Developer mode, off by default** (Settings > General > Developer). It adds
  one thing today: a **Components** tab in the cheatsheet showing every shared
  widget the shell is built from, live. Three views - a gallery of them by
  family, an audit table of every widget's height, radius, padding and font
  size so an inconsistency shows up as a number out of line, and a detail page
  where one widget can be put on any surface layer with its properties changed
  by hand. Every tile is the real widget, not a picture of one.

### Changed
- **The system monitor's orientation flip travels.** Toggling between
  the row and the column snapped every card to its new place in one
  frame; the box and the cards ride the spatial tier now, and the
  shadows drop for the motion like every other resize.
- **The privacy card speaks the shell's design language.** A shield in
  its error-toned Material shape heads the card; every section leads
  with its glyph in a shape of its own; the app rows and notes sit on
  tonal plates instead of floating on the card; and the controls are
  tonal buttons - the destructive pair on the error container - rather
  than bare glyphs.
- **The ambient RGB loop samples the screen without spawning anything.**
  Each sample was a `grim` process writing a downscaled JPEG to the cache
  directory. The colour now comes off the compositor's own frame through
  a screencopy view inside the shell - an 8x8 grab to tmpfs, quantized as
  before - which also frees the loop of its grim dependency (grim stays
  as a fallback). Measured: 1.3% of one core at five samples a second.
- **A dropdown ripples.** Both combo boxes - the closed button and every row
  of the open list - answered a press with a colour swap and nothing else,
  the one kind of control in the shell that did. They now draw the same
  hover, ripple and lift as a button, on a surface that paints without
  taking the press (the popup still opens on release, a row still chooses).
  The lift is on the button's parts rather than the button: a first cut
  scaled the whole control, and the list opened where the shrunken button
  was and stayed there. The list also arrives and leaves now - it fades in
  while it unfolds down from the button and folds back faster - where its
  old entrance animated an opacity from 1 to 1. A menu that flips above
  its button - no room below - unfolds from its bottom edge, out of the
  button, not away from it.
- **Option rows draw their icon plain.** Twenty-seven rows across Capture,
  Phone & Devices and the phone pages put their icon in a tile while the
  other hundred and forty did not, and a row wearing one read as a second
  control. The tile is a category title's; every option row now carries the
  icon without a background, and the opt-in that drew it is gone.
- **A settings row presses as a whole.** A switch row in a grouped list
  rippled and lifted inside its own bounds while the plate around it sat
  still, which read as pressing the label rather than the row. The plate is
  the pressed surface now - hover lift, ripple from where the pointer landed
  - and pressing the plate's padding presses the row.
- **The classic quick toggles are drawn from the same models as the Android
  ones.** Ten classic tiles re-derived their icon, state and actions from the
  services by hand and had started to disagree with the models. Two of them
  change on right-click as a result: Night Light opens its dialog (it used
  to flip Auto), and Bluetooth opens the devices dialog (it used to launch
  the external app). The Cloudflare WARP classic tile, which was hidden, is
  gone.
- **The cheatsheet is a window now, like Settings** - focused, moved and closed
  by the compositor, instead of an overlay layer. The layer took no keyboard
  input at all, which the keybind table never needed and the Components
  workbench does: its filter, text and number knobs typed into nothing.
- **The phone's notifications are drawn by the same card as the shell's own**,
  so they behave the same way: the swipe, the stack's lean, the group that
  expands and the buttons are one implementation instead of two that had
  already started to disagree. Replying to a phone notification and its app's
  own actions still work exactly where they did.

### Fixed
- **The privacy card names the recording source where one can be
  known.** A portal cast - a Discord or browser share, OBS's PipeWire
  capture - is a PipeWire video consumer carrying its app identity, and
  the Screen section now lists those by name (with the same
  electron-alias resolution the microphone rows use). Captures that
  never touch PipeWire - grim, gpu-screen-recorder - are anonymous by
  nature, so the generic line stays as the honest fallback.
- **The Edit Mode drawer's app search works, and looks like the shell.**
  The Dock tab's field could never be typed into: the chrome surface
  declares no keyboard focus so the mode's Escape ladder keeps working,
  and the field never got an exception. The surface now takes on-demand
  focus for exactly as long as the field holds it - the field's own first
  Escape hands the keyboard straight back - and the outlined box is the
  filled search row every other list carries.
- **Currency polish, three notes.** The flat 24h state draws a quiet
  dash instead of a rightward arrow that read as a signal; the hero
  chart line prefers the fetched 7-day series and is decorative only
  before any data exists; and the card sits on the same darker surface
  the weather card uses.
- **The currency chart line is back, and the flag sits on the code.**
  Three fixes: a chart canvas's first paint was requested before the
  canvas could accept one and never re-asked; a day (or month) with zero
  movement normalised to an invisible mid-band line - it keeps the
  decorative curve now, with the movement columns saying "flat" in
  numbers; and the base's flag rides the code's own painted end instead
  of a guessed offset that floated it into the divider.
- **The elastic corner pull reaches every widget.** Calendar and the
  world clock adopted the shell-owned resize without wiring the grip's
  rubber-band bow into their cards, and Notes - one offered size - never
  got a grip at all. All three bow now: the pull is forwarded to the
  cards, and the grip arms on every grid-sized widget, with a single-size
  widget's whole drag becoming the bow (the size row still appears only
  where there is a choice).
- **The world clock's settings face no longer shows the front through
  it.** The four city tiles kept drawing under the timezone pickers
  after the flip; they yield with it now.
- **A note row's hover fades instead of snapping.** The row flipped
  between its two colours with no motion at all - the widget audit's G10,
  closed with the tier every other hover already rides.
- **RGB devices no longer blink on every colour change, and colours fade
  instead of stepping.** Every write went through the `openrgb` CLI, and
  every CLI call is a fresh client handshake followed by a mode command -
  the mode command re-initialises the controller, which is the white
  blink, once per second while a colour was being adjusted and once per
  ambient sample. The service now keeps one client open to the SDK server
  (its own `openrgb --server` unless one already answers), the way the
  OpenRGB Effects plugin does: each controller is put into Direct mode
  once, and from then on only LED frames are sent, at 30 fps, ramping to
  each new colour. The CLI path survives only as the fallback for a server
  that never comes up; the palette debounce drops from 1000 ms to 200 ms.
- **Quick > Bar & Screen: the choice chips sit on one line again.** The
  four cards there use the segmented row without a label, and on that path
  the row's chip flow still sized itself from its own width - the circle an
  earlier fix had broken only for labelled rows - so Top / Left / Bottom /
  Right latched one per line when the page was built across frames. The
  flow now hands the layout its chips' natural width on both paths.
- **Custom AI providers see their API keys.** The keyring loads on demand,
  and neither the AI settings page nor "Fetch Models" ever asked for it - so
  with a local model selected the key fields read empty, typed keys were
  silently dropped, and every fetch went out with no key at all, which the
  provider refused. Both ask now, and the fetch waits for the keyring.
- **Removing a custom AI provider no longer hands its neighbour's API key to
  the one below it.** Keys are stored by the provider's position in the list,
  and removal blanked the removed slot only, so every provider after it read
  the slot above - a fetch with the wrong key, answered with a 401 the page
  called "Failed to fetch". The keys move up with their providers now. If a
  provider of yours already fetches with a 401, re-enter its key once.
- **Fetching models from a custom AI provider works with the URL you have, and
  says why when it does not.** A base URL pasted as `.../v1/models` had
  `/models` appended again, a 404 with an empty body, and "Failed to fetch".
  The base is normalised (a trailing `/models` or `/chat/completions` is
  dropped), and a failure now names the HTTP status and what to do about it -
  a 401 is the key, a 404 is the URL, no status is the server not answering.
- **The overview opens above fullscreen windows** (#339). It sat on the
  compositor's Top layer, which fullscreen windows are composited over, so in
  a game or a video it opened behind them. It moves to the Overlay layer only
  while it is open over a truly fullscreen window on that monitor, and stays
  on Top otherwise - closed, it never covers a game, so the game keeps its
  direct scanout.
- **The Visualizer desktop widget no longer slows the sidebars.** On a wide
  monitor it is several hundred bars, and each had its own height animation
  restarted on every one of cava's sixty frames a second, plus four colour
  mixes - a third of the shell's main thread, which is the thread the sidebar
  slide runs on. The bars now follow one smoothing filter over the whole
  array and take their colour from a palette; the widget costs a quarter of
  what it did per frame, measured, and looks the same. Two more things fed
  the same slowness: the wallpaper layer was being blurred by the compositor
  on every frame the widget changed it (opaque, so for nothing - a fifth of
  the GPU, measured), and behind a special workspace the widget kept moving
  under a fullscreen blur nobody could see it through. The layer rule is
  gone and the widget stands down while a special workspace is up. The rest
  of the music-time load was in the media surfaces: the media card's wavy
  progress slider repainted itself sixty times a second inside a sidebar
  kept loaded but closed, and the media widget's wave and ring rebuilt
  their geometry as hundreds of objects per frame, keeping the garbage
  collector busy. Sampled on the live shell: the main thread while a track
  plays went from about half a core to a quarter.
- **The Phone tab's header is one row of one size.** The device chip is the
  shared filter chip with a trailing arrow, and the connection and battery
  facts beside it are plain icon-and-label metadata with no container - a
  36px pill next to two 22px pills, all three looking clickable, is what it
  was.
- **The device roster's rows sit together.** A row that paints its own
  surface no longer gets the plate's padding and inset stacked under it,
  which was 24px of nothing between every two devices.
- **Replying to a phone notification: the field is whole, the three chips
  share the width, and the active Reply chip is readable.** The reply field
  drew its text past its top edge, the action row split its width in two by
  hand and pushed the third chip off the card, and the toggled chip used
  the primary colour under an on-surface glyph.
- **The cheatsheet opens on the key, not three seconds after it.** The
  Components tab built its audit table's sixty-two off-screen widgets at
  open whether or not the Audit was showing.
- **Following a link in a phone notification closes the phone's sidebar, not
  the other one.** The card closed the right sidebar whichever panel it was
  in; which sidebar a card sits in is now the notification backend's to say.
- **A contact's expand arrow stays where it belongs.** Opening the first
  contact in the list used to fling its arrow into the middle of the
  person's name and leave it there. Anything in the shell whose text
  animates as it changes could drift the same way; none of them can now.
- **The phone's notification buttons ripple again**, along with every
  other button that belongs to a group - the quick toggles, the settings
  chips, the AI chat controls. Their corners also settle into the
  pressed shape instead of snapping to it.
- **The phone's device list is drawn the way the rest of the shell's
  grouped rows are** - each device on its own plate, the group's outer
  corners rounded - instead of as a plain rectangle, and the device you
  picked is marked with a tick and its own colour instead of looking
  exactly like the ones you did not.
- **A Wallpaper Engine wallpaper with sound no longer plays it once per
  monitor.** The shell draws one live wallpaper per screen, and each was
  playing the audio, so on two monitors you heard the track twice, slightly
  out of phase. Sound now comes from one screen, chosen next to the volume
  button in the wallpaper picker; if that screen is unplugged the sound moves
  to another rather than going silent. ([#338](https://github.com/XephyLon/immaterial-impulse/issues/338))

- **The phone panel's buttons behave like the rest of the shell's.** Its
  notification bar is the same one the right sidebar draws, so its two
  actions square off and swell under a press instead of sitting still;
  the mirror, webcam and microphone cards ripple, dim when they cannot
  start, and can be reached from the keyboard; a contact card expands
  the way the Docker panel's cards do; and a notification group of one
  no longer offers to expand into nothing.
- **Settings rows show their choices in a row again.** Every segmented
  option row on every settings page had started stacking its buttons one
  per line - Bar position, Bar style, Group style and the rest - since
  the settings window stopped building all of its pages at once. A page
  built a few frames at a time gave the buttons a width they then kept.
- **The phone webcam's preview window closes with the session instead of
  freezing on screen.** Open the webcam, open the preview, then stop the
  camera: the preview used to stay up, frozen on its last frame, and nothing in
  the shell could close it - the player had been launched with no handle to
  hold. It now closes whichever way the session ends: you press stop, the
  stream drops on its own, the phone goes away, or the shell restarts. The
  Preview button is a toggle too, so you can close the window from the page you
  opened it from.

### Added
- **The Phone tab pairs your phone over Wi-Fi instead of telling you to open a
  terminal.** The Android Apps page used to print the two commands Android 11
  and newer needs — `adb pair host:port code`, then `adb connect host:port` —
  and leave you to retype them after every toggle of the Wireless debugging
  switch. It now offers them as a form: an address and the six-digit code the
  phone shows, a Pair button, then the connect address and a Connect button,
  with whatever adb answered printed under each step. Where `avahi-browse` is
  installed, **Find the ports** asks the network which ports the phone is
  advertising and fills both addresses in; the address KDE Connect already
  reaches the phone on is filled in either way. The six-digit code is still
  read off the phone — it is generated per pairing and published nowhere.
- **Opening a Phone tab page fades the tab back behind it.** Contacts and
  Android Apps slide in over a tab that now recedes and dims as they arrive,
  rather than sitting there at full strength underneath. It follows the
  animation-speed slider and the reduce-motion switch like the rest of the
  shell.
- **The Phone tab.** The paired phone gets a tab of its own in the left
  sidebar, beside Intelligence, Translator and Media. Top to bottom: the
  device on a chip whose arrow opens the list of every device the daemon
  knows, with its cellular network (or its wireless address) and its
  battery as pills beside it; one row of six round actions — ring it, ping
  it, send it your clipboard, send it a file, share the clipboard as a link
  or as text, and browse its storage; cards for Contacts and Android Apps
  that say how many contacts synced and whether this machine's scrcpy can
  do App Mode; your phone's notifications filling the rest of the panel,
  grouped by app, with swipe-to-dismiss, inline reply, action buttons and
  copy; and a toolbar to re-read them, count them or clear them all. Files
  dropped anywhere on the tab are sent to the phone, and pairing requests
  appear as cards at the bottom. The right sidebar's Phone quick toggle
  opens this tab instead of its old dialog, which is gone.

  Everything the last few releases built for the phone but had nowhere to
  show is now reachable, and the phone's notifications stop appearing twice.
- **Phone Connect warns when your phone's battery is low, and can send it
  files, links and your clipboard, or open its storage.** A desktop
  notification arrives once when the paired phone drops below 20% while
  not charging, and again when it is back at 25% or plugged in. The phone
  service can now share files picked with the file dialog, a link or a
  piece of text from the clipboard (a link is recognised and sent as one),
  and browse the phone over SFTP, opening its internal storage rather than
  the bare mount. The device you pick in the panel is remembered across
  restarts, with the last five picks kept for the list. The buttons for the
  new actions are the Phone tab's six-button row, in this same release.
- **Your phone's notifications are mirrored into the shell.** With a phone
  paired through KDE Connect, the shell reads its active notifications off
  the daemon as they arrive, keeps them grouped by app, dismisses one on the
  phone itself rather than only hiding the card, replies inline where the app
  allows it, and remembers the list across a restart. While the phone is
  reachable, kdeconnectd's own desktop pop-ups of those same notifications
  are no longer shown beside them. The Phone tab draws them, in this same
  release.
- **The phone's contacts reach the shell.** A new `PhoneContacts` service
  reads the vCards KDE Connect syncs to `~/.local/share/kpeoplevcard`, keeps
  the list live as the phone syncs (and parses the names Android soft-wraps,
  which used to come out truncated in the fork this is ported from), searches
  it by name, organization, address or digits, hides the number-only cards
  anti-spam apps leave behind - never a starred one - and can open the
  phone's dialer or SMS composer for a number over adb, saying why when it
  cannot. It is what the Phone tab's Contacts card counts.
- **The phone's screen, camera and microphone reach the desktop.** Groundwork
  for the Phone tab: scrcpy mirrors the phone in a window and opens one
  Android app on a virtual display of its own (scrcpy 4+, "App Mode"), the
  phone's camera becomes a `/dev/videoN` webcam through DroidCam, and its
  microphone becomes a `DroidCam-Mic` input that any app can record from -
  through scrcpy with no app on the phone, or through DroidCam. Every one of
  these is optional: nothing is added to the installer, each tool is probed
  when the shell starts, and what is missing is answered with the install
  command for Arch, Fedora and Debian. The settings live under
  `phone.*` in config.json (mirror flags, app-mode display, webcam and
  microphone connection); the Phone tab is where they are reached from.
- **The Phone tab's feature cards, its sub-pages, and a Devices & Phone
  settings page.** The bottom of the Phone tab is three cards — the scrcpy
  mirror, the phone as a webcam, the phone as a microphone — that say which
  of the five things they are (not installed, no phone, connecting, ready,
  running), grow while one is running to carry how long it has been up, a
  Stop button and its own quick actions, and take a file dropped on them to
  send to the phone. A card for a tool that is not installed opens a guide
  naming exactly what is missing, with the install command for Arch, Fedora
  or Debian and a button to copy it, and a Re-check that closes the guide
  once it is satisfied. A pairing request joins the same stack. Behind the
  tab's two navigation cards: Contacts, which searches the phone's contacts
  by name or number, shows their own photos, stars the ones that matter and
  opens the phone's dialer or SMS composer; and Android Apps, which lists
  what the phone has installed, starts one on a display of its own, and
  shows what is already running with Focus, Close and Stop all. The webcam
  and microphone each get a page with their toggle and settings. Settings >
  Devices & Phone collects everything the tab persists — the panel's cards,
  the contacts rules, and the mirror's connection, options and App Mode.
- **Phone Connect shows your phone's wireless address and cellular network,
  and answers pairing requests.** The panel reads the address KDE Connect
  reaches the phone on and its cellular network type (LTE, 5G, …) alongside
  the battery. When another device asks to pair with this one, the panel
  shows the request as a card with Accept and Decline, so pairing no longer
  needs KDE Connect's own window — and it is answered only for the device
  that asked.
- **`deploy-shell`, for maintainers**: copies this checkout's shell to
  `~/.config/quickshell/imi` and refuses when the copy would take another open
  PR's work off the running shell, naming the branches it would roll back. It
  also records the SHA and branch it deployed in `.deployed-from`, so what is
  live can be read rather than inferred from whichever branch you happen to be
  on. Replaces an `rsync --delete` one-liner that had done exactly that revert.

### Changed
- **The Phone tab's device roster unrolls instead of appearing all at once.**
  Clicking the device chip used to put the list of every device the daemon
  knows on screen in one frame and take it away in one. It now unrolls from
  under the chip and folds back the same way, and it is drawn by the same list
  the Wi-Fi and Bluetooth device pickers use, so a device joining or leaving
  the network arrives and leaves as a row rather than making the list jump. The
  reveal follows the animation-speed slider and the reduce-motion switch like
  the rest of the shell.
- **The right sidebar's quick sliders arrive one card at a time.** Each slider
  card now fades in, zooms up from slightly smaller and rises into place —
  the bottom row first, brightness last — while its fill still sweeps up from
  zero with the icon turning, as before. It is the sibling fork's slider
  entrance on the shell's own motion tiers, so the animation speed slider and
  reduce motion reach it.
- **Settings > Capture reads as one grammar of rows.** Subsection headers lead
  with an icon; every Quality and selection option carries an icon; a live line
  under Quality says what the chosen tier costs on this screen ("~44 Mbps -
  5120x1440 - 60 fps on this screen", computed from the monitor the window is
  on, with the frame rate capped at the screen's refresh); toggle rows carry an
  icon chip; the codec dropdown marks Auto as recommended; the path fields
  float their labels into the field; and every explanation moved from a
  paragraph under its row to an (i) you hover. The other settings pages are
  unchanged and follow in later releases.
- **The phone panel is laid out like a phone panel, and it moved.** The
  device sits on a chip whose arrow opens the list of every device the
  daemon knows; its connection, battery and cellular network are pills
  beside it; the actions are one row of round buttons instead of buttons
  repeated on every device row; the middle of the panel is reserved for
  your phone's notifications; and secondary features — pairing requests
  among them — stack as cards at the bottom. It landed as a dialog in the
  right sidebar and ships as the Phone tab in the left one, which is where
  the rest of this release's phone work is reached.
- **The Phone tab's footer toolbar.** The count under your phone's
  notifications reads "7 notifications" rather than "7 notif.", and "1
  notification" for one; it says "Device offline" instead of counting when the
  device on the chip is not there; and a longer count elides inside its pill
  rather than being drawn over the buttons beside it. Those two buttons — sync
  and clear — are a little wider than they are tall now, so the row reads as
  three soft rectangles rather than two circles around a pill, and their icons
  sit dead centre instead of a pixel and a half to the left.

### Fixed
- **A phone feature no longer says "ready" when the tool it needs cannot
  start.** The shell checked whether scrcpy, adb and DroidCam CLI were
  installed and not whether they run. On this machine `droidcam-cli` was
  installed and died on startup with a missing `libswscale.so.9` — the package
  was built against an older ffmpeg than the system now ships — so the webcam
  card read "ready", pressing it did nothing, and the message on screen asked
  whether the DroidCam app was open on the phone. The three tools are started
  as well as located now, and a tool that cannot start says so: which library
  is missing, and that the package needs rebuilding rather than installing.
  The Android Apps page tells the same three states apart too — adb missing,
  adb unable to start, and adb working with no phone on it — where it used to
  assume the first two away.
- **Turning the phone webcam off no longer kills the phone microphone.** The
  webcam and the microphone are both `droidcam-cli`, and the shell told them
  apart by looking for `droidcam-cli` in the running process's command line -
  which the microphone's contains too. After a shell restart with only the
  microphone running, the Webcam card came up claiming a stream that did not
  exist, and switching it off sent the stop signal to the microphone instead.
  The two are told apart properly now, and the same mistake could no longer
  have let the webcam's stop reach a scrcpy microphone either.
- **The Phone tab's webcam and microphone state stops disappearing
  altogether.** The probe the two cards read builds one line of JSON, and
  when it could not work out the connection's port it left that field empty -
  which is not a missing port but a broken line, so the shell threw the
  *whole* answer away: the webcam device, the audio source and both running
  flags with it. A configured port shorter than three digits was enough on
  its own. The probe also reported a webcam as running when the process it
  had just seen exited underneath it, and lost the port and the address of
  any session it re-adopted after a restart.
- **A frozen phone mirror stops reading as a running one.** scrcpy is
  talkative, and the supervisor that owns it only read what it printed after
  it had finished - so once scrcpy had said about 64 KiB it stopped dead
  waiting for someone to listen, and since it never exited, the mirror card
  stayed on "running" over a window that had frozen or died, with no way back
  but a restart. The Phone tab also stopped answering clicks for up to half a
  minute while it fetched the phone's app list, and an event lost to two
  writes colliding could leave a session on screen with no window behind it.
  Stopping the shell now really does stop every mirror it started, rather
  than only when it shuts down cleanly.
- **Installing DroidCam on Arch no longer claims success when it failed, and
  installs what the webcam needs.** The Arch branch of the installer printed
  "✓ DroidCam installed" whatever the AUR helper did, and the closing note
  then told you the Phone tab's cards should read "Ready". It also never
  installed `v4l-utils` or `android-tools`, both of which the other
  distributions' branches install and without which the webcam cannot be
  found at all - so a completed install could leave the feature dead. On
  every distribution, a failed download or extract no longer runs the
  DroidCam installer as root from whatever directory you happened to be in.
- **The DroidCam microphone stops collecting duplicate audio devices.** On a
  sound server that names the null sink's monitor with a prefix, the setup
  script could not see the sink it had loaded a moment earlier and loaded
  another under the same name on every launch, while the teardown removed
  exactly one per call. A setup that fails now takes its own sink back with
  it.
- **The Stop button on a running Phone tab card draws its icon and its label in
  the middle.** They were pressed against the button's left edge with the rest
  of it empty, and the gap between the icon and the word grew as the button did.
- **The Phone tab's clear-notifications button stops drifting out of its
  circle.** The moment the notification count first changed, that button's icon
  slid up and to the left and stayed there for the rest of the session - and
  blinked out entirely while it moved, leaving an empty pill behind. Its
  neighbour was unaffected, which is what made it read as one broken button.
- **The Phone tab's Android Apps page says what to turn on when it cannot
  reach the phone.** App Mode drives the phone over ADB, which is a
  different link from the one KDE Connect pairs: with a phone reachable on
  the network but no `adb devices` entry, the page drew one thin line of red
  text ("Phone not reachable over ADB") and an unhelpful "No apps yet" under
  it. It now draws one panel in the error colours, carrying both ways to get
  a device - USB debugging over a cable, and wireless debugging with the
  pair-and-connect Android 11 and newer needs after every toggle - and the
  empty state stays out of the way until there is a phone that answered with
  nothing. As soon as a device appears the panel goes and the app list is
  fetched without a click. The empty state's own line is held to a readable
  measure and centred instead of running the full width of the panel.
- **Contacts with an Arabic name fit inside their row.** In the Phone tab's
  Contacts list, a contact whose name is written in Arabic had its number and
  its avatar drawn below the bottom of its own card - a row taller than the
  card holding it - and with Latin names the avatar sat against the card's
  bottom edge with almost no room around it. The row was a fixed height, and
  Arabic sets taller than Latin at the same text size. Every row now takes the
  height its own contents need, in any script, with the same breathing room
  above and below.
- **The Phone tab's Phone Webcam and Phone Microphone pages fit the panel
  again.** Both pages were drawn wider than the sidebar and shifted left, so
  every label was cut off at the panel's left edge — the error banner read
  "m did not start - is the DroidCam app open on the phone?", the section
  headers read "ra" and "ra settings", and the resolution row ran off the
  right edge. Both pages now take the width the panel gives them, and a long
  message from the camera or the microphone wraps inside its banner instead
  of stretching the page around it.
- **The scrcpy Mirror card stops claiming a mirror it never opened.**
  Clicking it on a phone your machine can reach over KDE Connect but that
  `adb devices` does not list flipped the card to "scrcpy Mirror / Mirror is
  running · click to focus its window" with a tick and "Active for 0s" — and
  a second later dropped it back to exactly the line it had before the
  click, with the icon missing from its badge. The card now says
  "Connecting scrcpy…" for the whole time between the click and the answer,
  and a launch that fails shows why it failed instead of quietly returning
  to where it started. The badge keeps its icon throughout.
- **The Phone tab's message bar stays inside the panel.** A long error — for
  instance "DroidCam did not start - is the DroidCam app open on the phone?"
  — drew as a red bar clipped at the panel's edge with its text running off
  the end. It now wraps and stays within the tab, however long the message.
- **The Phone tab's Contacts and Android Apps pages draw their contents
  again.** Contacts showed its count — "147 of 150 contacts" — and then an
  empty page, and Android Apps drew its big empty-state icon on top of its
  own search box, hiding the line explaining that the phone was not
  reachable. Both pages were being given no height to draw into, so a full
  list showed nothing and an empty one spilled over the header above it.
  Each page now fills the room under its title bar: the list runs to the
  bottom of the panel, and an empty state centres in what is left.
- **Phone notifications show the app's icon.** A mirrored notification drew
  the app's name and its text but never the icon KDE Connect sends with it.
  The icon is now on the card, beside the app name, with the same
  guessed-glyph fallback the shell's own notifications use for an app that
  sends none.
- **Settings stops switching off the debounce on every config write in the
  shell.** Opening the settings window was never actually required: the
  settings page host is built while the shell starts, and it asked for its
  config writes to be flushed immediately and never asked for that to stop —
  so from startup onward every setting written anywhere in the shell, by any
  panel, rewrote the whole of `config.json` and read it straight back, once
  per value instead of once per burst. Settings still writes immediately while
  its window is open, and only while its window is open.
- **The Phone tab's Mirror, Webcam and Microphone cards say what is wrong
  instead of nothing.** Three separate silences, all of which read as the card
  ignoring the click. A card whose feature drives the phone over ADB — the
  scrcpy mirror, and the microphone wherever scrcpy is installed — now says "No
  device over ADB" *before* you click it, if `adb devices` lists nothing,
  instead of offering to open a window it cannot open; plugging the phone in
  while the tab is open clears it. A launch that fails puts its reason on the
  card, where before the webcam and the microphone dropped straight back to
  "Tap to start" with the reason recorded nowhere you could see. And the three
  services' own error reports now reach the tab's toast, which had only ever
  been connected to the phone link's.
- **Both sidebars open on the monitor you are using again.** On a multi-monitor
  setup the left and right sidebars had started opening on whichever screen was
  focused when the shell started, wherever you actually were — the same thing
  the overview did in 0.30.0, arriving through the same change (the panels' own
  surfaces now outlive the gesture, and a surface that is created once has to
  say which screen it lives on). Each sidebar is one surface per screen now, and
  every open picks the focused monitor afresh. Pinning the left sidebar reserves
  space on that screen only.
- **The left sidebar's tabs stop disagreeing with the page on screen.** After
  clicking a tab once, swiping the panel — or following a link into a tab, such
  as the Phone quick toggle — moved the page without moving the tab bar.
- **The shell no longer freezes for two thirds of a second while it starts.**
  Settings built all fifteen of its pages — about 24500 items — in one go the
  moment the configuration loaded: measured at 618ms with nothing on screen able
  to move, bar and dock included, and paid on every launch whether or not the
  window was ever opened. The pages are built one at a time in the background
  now, and the same measurement reads 64ms. Switching pages stays as immediate
  as it was; a page reached before the background pass gets to it says
  "Building this page…" for the moment it takes, instead of showing an empty
  pane.
- **Leaving a Discord voice channel no longer kills the voice bridge.** Discord
  reports the empty selection as a null payload, which the bridge treated as a
  crash; after five restarts the widget gave up with "Discord bridge stopped
  after repeated failures". A null payload is read as an empty one now.
- **Discord started after the shell is picked up on its own.** With Discord
  closed, or its RPC socket dropped, the voice widget used to sit on "Start
  Discord, then reconnect" until you pressed connect. It now retries by itself,
  backing off from one second to every thirty, and stops the moment it
  connects.

## [0.32.0] — 2026-08-27

One behaviour change, small in code and large on the hand: picking a section
in Settings scrolls the page there instead of snapping.

### Changed
- **Picking a section in Settings scrolls to it instead of jumping.** Choosing
  a category in the left tree (or landing on a search hit) used to snap the
  page to that section in one frame; the page now glides there on the same
  curve every other scroll in the shell uses, and any wheel or drag takes over
  from wherever it got to.

## [0.31.2] — 2026-08-27

Two fixes found on one button and applied everywhere the same spelling lived:
icon buttons centre their glyph, and the text field's confirm button arrives
and leaves smoothly instead of snapping.

### Fixed
- **Icon buttons draw their icon in the middle.** The presets "save" button, the
  password-reveal eye, the phone panel's ring and send buttons, the wallpaper
  selector's close and audio buttons, the edit-mode menu's back arrow and the
  clock-depth inspector all drew their glyph up-left of centre. The glyph was
  told to centre itself in a way its button ignores; it now says so in the way
  the button honours.
- **The presets "save" button arrives and leaves smoothly.** It used to pop in
  at full size the moment you typed a name and vanish the moment you cleared
  it, shoving the text field a button-width in one frame each way. It now
  glides in and out like the bar's pills, and the field reflows with it.

## [0.31.1] — 2026-08-26

Three fixes: the overview really does follow the focused monitor now (the
0.31.0 fix only got the first open right), no more empty pill at the end of a
bar section, and the notifications section stops painting over its neighbours
when the sidebar has no room for it.

### Fixed
- **The overview opens on the focused monitor every time, not just the first
  time.** 0.31.0's fix picked the right monitor for the first open and then
  kept reusing that monitor's window for every open after it — on one
  monitor invisible, on two the same bug as before (#297, reopened). Each
  open now asks which monitor has focus.
- **No more empty pill in the bar.** With the timer or the submap indicator
  at the end of a bar section, an empty rounded stub sat beside the last
  widget whenever the pill had nothing to show — the group around the pill
  kept its padding after the pill itself had collapsed. A group whose
  content is gone now goes with it, and the widget next to it gets the
  rounded end it is entitled to. Edit mode still shows every slot so an idle
  pill can be dragged.
- **The notifications section no longer bleeds over its neighbours.** When
  the media player and an expanded timer/calendar left the right sidebar no
  room for notifications, the empty-state bell, "Nothing" and the
  "0 notifications" pill still painted, over the media player and the tab
  row. The section now paints nothing when it has no room and hides its
  list until there is space for the status row and a line above it.

## [0.31.0] — 2026-08-26

The motion language's second half: the panels arrive composed, with their
pieces cascading and converging into place, instead of snapping on. Plus the
overview back on the monitor you are actually using, and the to-do list's
buttons aimed at the right row.

### Changed
- **The panels arrive composed instead of snapping into place.** The bar's
  popups open at their full height first and then let the sections below the
  first fold cascade in — the top section is there on frame one, so a popup is
  readable the instant it opens, and switching popups by hovering along the
  bar never blinks content. The desktop menu's rows arrive in sequence the
  same way. The sidebars got the fuller treatment: sections cascade behind the
  panel's own slide, the quick-toggle tiles converge from their side of the
  grid, the slider fills sweep up from zero with their icons turning with the
  fill, the calendar ripples in diagonally, and the notification status row
  converges into place. The left sidebar and the AI pane materialize the same
  way. Exits stay rigid — everything rides out with the panel, nothing
  cascades on the way out. Dialogs deliberately do not do any of this: a
  cascade on a question you were interrupted to answer is latency.
- **Text that changes now moves.** The bar's media label and the weather
  temperature slide to their new value instead of swapping, and adding or
  finishing a task in the to-do list animates the row in or out.

### Fixed
- **The overview opens on the monitor you are using again.** Since 0.30.0 it
  opened on whichever monitor had focus when the shell started — usually the
  primary — no matter where the cursor was, because the overview's window is
  created once at startup now and the compositor places a window without a
  screen of its own on the monitor focused at that moment. There is one
  overview window per monitor now, and each open picks the focused one.
  (#297)
- **The to-do list's buttons no longer aim at the wrong row after a delete.**
  Each row resolved its task by an index taken when the row was built, so
  deleting a task left every row below it one off. Rows now find their task
  at click time — by identity, and by content on older Quickshell builds where
  the model hands each row a copy (the Gentoo package pins one), where every
  done/delete click had been a silent no-op.

## [0.30.2] — 2026-08-26

Two more "silently wrong" settings fixes and one decode the selector never
needed to pay.

### Fixed
- **The EasyEffects quick toggle tells the truth about a failed launch.** The
  toggle flipped to "on" the moment it was clicked and nothing ever checked
  whether the daemon actually came up, so a failed launch left it saying on
  for the rest of the session. It still answers the click immediately, and
  now verifies against the real process list a grace period later — a launch
  that died is reflected instead of trusted.
- **The Screens settings section is findable again on one monitor.** Like the
  Clight section in 0.30.1, Settings search offered "Screens" while the
  section hid itself whenever only one monitor was connected — with a sharper
  edge: a laptop undocked with a stored screen filter hid the only control
  that can clear that filter. The section now stays on the page; the chooser
  appears when there is something to choose, and a single screen with no
  stored filter gets a caption instead.

### Changed
- **The wallpaper selector opens lighter.** Its blurred backdrop decoded the
  current wallpaper at full file resolution on every open; the decode is now
  bounded to the size of the backdrop it is drawn into.

## [0.30.1] — 2026-08-24

Three fixes, all in the "silently wrong" family: terminal theming that died on
a leftover symlink, a settings section that search offered but could not show,
and settings rows that hid by leaving an empty plate behind.

### Fixed
- **Selecting the tmux config in the installer now actually themes tmux.** The
  palette switch themes cava, btop, tmux and kitty in one run, and a single
  unwritable config — measured: a dangling `~/.config/btop` symlink left behind
  by a previous dotfiles suite — aborted the run before tmux's theme was ever
  written, silently, on every wallpaper change. Each app now themes
  independently, and a broken one is named in the log instead of taking the
  rest down.
- **The Clight settings section is findable again on machines without clight.**
  Settings search offered "Clight" (it is in the Services page's section list)
  while the section itself was hidden whenever the daemon was not installed, so
  searching for it landed on an unrelated scroll position. The section now
  stays on the page: without clight it is a single line saying what the
  integration does; the controls still appear only when the daemon is there.
- **Hidden settings rows no longer leave empty plates behind.** A GroupedList
  row hidden with `visible:` kept its full-height background plate — a blank
  band in the group. Thirteen rows across the Services, Wallpaper and Sidebars
  pages and the bar's network popup carried the wrong spelling; all now use the
  `rowVisible` contract, and a new lint keeps the next one out.

## [0.30.0] — 2026-08-24

The panels stop rebuilding themselves: the sidebars and the overview keep one
window for the life of the shell and only their panels move, which removes the
last per-gesture stalls — and this release pays everything that owed, from the
keyboard grab to the input regions to the blur. Alongside it, a performance
round across the services, the clock settings finally filtering by style, and
wallpaper depth reachable for Wallpaper Engine scenes.

### Added
- **You can put a widget away by dragging it back into Edit Mode's drawer.**
  Dragging a widget out of the drawer has always placed it on the desktop; the
  other direction did nothing. Now letting a widget go over the open drawer
  takes it off the desktop, and the drawer lights up while you are over it so
  you can see the drop will remove rather than move. Ctrl+Z brings the widget
  back exactly where it was, not at some default spot — the drag never writes a
  new position on its way out. Which section the drawer happens to be showing
  makes no difference; the panel is the target, not the list on it.
- **You can choose which widgets the lock screen shows.** "Show desktop widgets
  while locked" was all or nothing: every widget on your desktop, or none of
  them. Edit Mode's Lock section now lists your widgets under that switch, and
  clicking one adds or removes it from the lock screen alone — including a
  widget you want *only* while locked, which no arrangement of one setting
  could express. It works the way the arrangement already does: the lock screen
  follows your desktop's widgets until the first pick, and the drawer says
  which of the two it is doing and offers "Click to show the desktop's widgets
  again" to go back. Nothing changes until you pick something, and the switch
  above still decides whether the lock screen shows desktop widgets at all.
  Your presets carry the choice.

### Changed
- **The shell idles lighter and boots smoother.** A round of performance
  fixes, none of which changes how anything looks:
  - The overview's window now stays alive like the sidebars' do, so
    Super+Tab no longer pays a rebuild stall on every press.
  - The icon-search database (1.7MB) loads the first time you search
    symbols instead of at startup.
  - Caps/Num Lock state comes from the keyboard's own LEDs through one
    tiny watcher instead of asking Hyprland 3 times a second.
  - Network events feed the shell through a single monitor that cleans up
    after itself - crashed shells used to leave silent nmcli processes
    behind (30 were found on the dev machine).
  - The dock's window previews stop being captured the moment the popup
    hides, decorative cookie spins tick at 30Hz instead of every frame,
    and icons share font engines instead of minting near-duplicates.
- **The clock widget's settings show only the options for the clock style you
  picked.** Digital, Cookie and Pixel each have their own options, and all
  three sets used to be listed together — eleven Cookie rows under a Digital
  clock. Now a style's rows appear only while that style is selected for the
  desktop or for the lock screen (the two can differ). Plugin authors get the
  same: an option can declare `visibleWhen` against another option's value.
- **The session screen and the settings pages now arrive in sequence instead of
  all at once.** The session screen's nine action buttons and a settings page's
  sections each fade in one after the other, a few hundredths of a second
  apart, so a panel reads as content arriving rather than as a picture
  switching on. The wave is bounded, so a long list never cascades for seconds,
  and anything hidden in the group is skipped rather than leaving a gap in the
  middle of it. Both the animation speed slider and the reduce-motion switch
  reach it: with reduced motion the whole thing is gone and everything is
  simply there. The right sidebar was given the same treatment during this
  cycle and has had it taken back off — it opens in one frame with its own
  slide, the way it always did.

### Fixed
- **Wallpaper depth is reachable for Wallpaper Engine wallpapers.** The
  depth service could already cut a subject from a live scene's still, but
  the button that opens the picker only existed on the Local tab - from the
  Wallpaper Engine grid the feature was unreachable. The same button now
  sits in that tab's toolbar too.
- **The overview's frost covers the whole card again.** Keeping the
  overview's window alive left its blur region stuck where the half-built
  grid had been on the very first open - a sharp unblurred band down the
  card's left edge. The region now follows the card through every rebuild.
- **Typing works again the moment a sidebar opens.** Keeping the sidebar
  windows alive (the stutter fix below) quietly broke their keyboard: a
  window that is never re-created never gets the keyboard grant that used to
  arrive with its creation, so keys only reached a sidebar after the mouse
  happened to touch it — the left sidebar's AI chat felt dead, and Escape
  wouldn't close it. The focus system now hands the keyboard to whichever
  panel just opened. Confirmed for both sidebars: typing lands immediately,
  Escape closes, clicking outside closes, and clicking the bar while a
  sidebar is open still leaves it open.
- **The clock settings filter actually filters now.** The per-style option
  rows were annotated in the last cycle but Settings > Widgets kept showing
  all of them regardless of the selected style: the rules survive as data,
  but on their way to the settings page they cross a Qt type boundary that
  turns JSON lists into list-like objects a strict `Array.isArray` check no
  longer recognises, so every rule fell back to "just show the row". The
  evaluator now accepts those objects, and switching Digital / Cookie / Pixel
  swaps the visible rows immediately.
- **Opening a sidebar no longer freezes the shell for a moment.** Every open
  rebuilt the sidebar's window from scratch, and while that happened every
  other thing the shell draws — the bar, the dock, the desktop — stopped for
  about fifteen frames. The windows now stay alive and only the panel slides,
  on the same motion as before, so the open is immediate. The left sidebar
  also stops being able to hold the keyboard while it is closed.
- **The overview opens and closes with an animation instead of snapping.** It
  appeared and vanished on a single frame at both ends. Now the search bar and
  the workspace grid grow out of the top of the screen together and settle with
  a small bounce, and on the way out they shrink and fade — the window stays on
  screen for as long as that takes rather than being torn down the instant you
  press the key, which is what left nothing to animate before. The frosted
  backdrop behind the cards no longer appears before them or lingers after them.
- **The password box in the authentication prompt draws the same animated
  characters as the lock screen.** Both are the shell asking for your password,
  and only one of them showed the shell's own masked characters — a Material
  shape per letter, each popping in as you type it. The prompt showed plain
  system dots. It is one control now, so the two cannot drift apart again, and
  clicking the box focuses it whichever prompt you are looking at.
- **A dialog's buttons line up with the dialog.** Every dialog's action row sat
  eight pixels outside the box the rest of its content lines up with, which
  also left less space under the buttons than above the title. It shows most in
  the authentication prompt, where the OK button hung past the right edge of
  the password box directly above it.
- **Every dialog gives its content more room.** A dialog card held its content
  23 pixels in from its edge, and 23 was not a spacing choice — it is the size
  of the card's rounded corner, which the padding had been quietly spelled as.
  It is 32 now, on the same 8-pixel rhythm everything else in the shell lays out
  on. All ten dialogs still fit what is in them, and lists and rules that run to
  the card's edge still reach it.
- **Cancel now looks like a button.** In the authentication prompt, OK carries a
  filled accent container and Cancel was a bare word beside it, which reads as a
  link rather than as the other half of a choice. It has an outline now, and the
  two sit a little further apart so both edges are legible. The rule is general:
  wherever a dialog's confirming action is filled, its dismissing action is
  outlined — a dialog whose buttons are all flat is unchanged.
- **Edit Mode's widget drawer stops drawing over an open sidebar.** The drawer
  shares the right sidebar's edge and sits on a layer above it, so a sidebar
  left open was painted through by the panel. Entering Edit Mode now closes both
  sidebars, and they stay closed for as long as the mode is on — the same thing
  the mode already does to a bar popup that would sit over the bar it is
  editing. Nothing about the sidebars changes outside the mode, and they are not
  reopened for you when you press Done.
- **The wallpaper selector now leaves the way it should.** Closing it ran the
  *entrance* curve: the panel lurched a third of the way off screen in a single
  frame and then coasted, instead of easing away. Measured off a 60fps capture —
  659px of travel whose first frame took 32% of it, matching the entrance curve's
  predicted 32.6% against the exit curve's 1.3%.
- **...and it now arrives instead of appearing.** It had no entrance animation at
  all — measured, 99.6% of its 690px of travel landed in a single frame, so the
  panel popped in and slid out. It also vanished with a seventh of its exit still
  undrawn. It now grows and fades into place under the bar and dissolves the same
  way, which is what the rest of the shell's menus already do; nothing travels the
  height of the screen any more.
- **Edit Mode's widget drawer stops freezing half way through its own
  animation.** The panel reached its full width 226ms into a 500ms transition
  and then stood perfectly still for the remaining 271ms, while the desktop it
  pushes aside carried on drifting and settling. One gesture, two halves, two
  different motions. The panel now rides the same curve the desktop does, all
  the way to the settle.
- **Edit Mode's widget drawer fills instead of arriving fully furnished.** The
  panel and everything in it slid in as one solid block, so a 500ms reveal had
  nothing happening in it after the first fifth. The panel now arrives as a
  surface and its contents follow it in — the heading, the section chips, the
  hint and the list, each landing where it will sit rather than sliding there.
  Closing is unchanged on purpose: the contents stay drawn and ride the panel
  off in one piece.
- **Forty animations across the shell stopped moving at a constant speed.** Each
  one asked for a motion tier's timing and never picked up its curve, so it slid
  linearly instead of easing — the util buttons in the bar, the settings fields
  and navigation chevron, the session screen's boot entries, the volume mixer's
  mute fade, the desktop widgets' resize and toggle handles, the media transport
  and Discord voice ring, the display arrangement's monitor tiles, and every
  window and highlight in the niri-style overview. They now move the way their
  neighbours already did.
- **The niri-style overview scrolls smoothly to the workspace you switch to.**
  Its scroll had asked for one tier's timing and another's curve, which resolved
  to no curve at all.
- **Edit Mode no longer draws on top of a scratchpad.** Summoning a special
  workspace while editing left the toolbar, the tab bar and the widget drawer
  painted over the window, with the desktop they belong to hidden underneath
  it — so the mode was not merely untidy, it was unusable: the widgets being
  arranged could not be seen at all. The chrome now drops to the desktop's own
  layer while a special workspace is up, so the compositor blurs and dims both
  halves of the mode together instead.
- **Settings no longer claims grim is missing when it is installed.** The
  "Only while fullscreen" row under Wallpaper & Colors read a capability flag
  that was only ever probed when the ambient RGB loop was switched on — so with
  that loop off, the row reported grim as not found on a machine where it was
  installed and working.
- **Edit Mode's widget drawer no longer sits flush on the screen edge.** The
  panel's rounded right corner met the edge of the display with nothing between
  them, while its other side had a full margin against the desktop. It now
  keeps a gap on the side it opens against.
- **Edit Mode's desktop preview got bigger.** The toolbar and the tab bar each
  reserved a full margin of air between themselves and the edge of the screen,
  on the axis that decides how far the desktop shrinks — so both came straight
  off the preview. The outer gap is now half the inner one, and on a 5120x1440
  display the preview grows from 4380x1232 to 4466x1256.
- **"Edit layout" no longer looks like a button you can press.** It was an icon
  beside a label sitting flat in a row of controls, which is exactly how the
  toolbar draws an unfilled button. It now reads as the title it is, with a
  rule separating it from the buttons.
- **The password prompt looks like the rest of the shell.** The dialog that
  asks for your password when something needs administrator rights was drawn
  out of Qt's own parts rather than the shell's: a boxed, outlined text field
  with the word "Password" floating in a notch cut through its border — a shape
  that appears nowhere else here — and two flat text buttons, so nothing said
  which of Cancel and OK the dialog was actually asking for. The field is now
  the same filled pill the lock screen asks for your password in, OK carries a
  filled accent, and the dialog card casts a shadow like every other floating
  panel in the shell. Every dialog gets that shadow, not just this one.
- **Running the test suite no longer opens windows over what you are doing.**
  Five test harnesses started the shell on the session's own display, so a
  suite run flashed real windows across the screen — and a harness that draws a
  panel there covers it outright. They bring their own headless compositor now,
  like the rest already did.

## [0.29.0] — 2026-08-20

The on-screen keyboard becomes a real keyboard: every key a full-size board
has, the key you are holding lit up on it, and Caps and Num showing their
locks. Its shadow — and the wallpaper selector's — stops being frosted by
the compositor.

### Added
- **The on-screen keyboard is a full-size keyboard.** It was missing Caps
  Lock (the home row started at `a`), both Super keys, Scroll Lock, Pause, the
  navigation cluster (Insert, Home, PgUp, Delete, End, PgDn), the arrow keys
  and the entire numpad. All of them are there now, in all three layouts — a
  keyboard layout decides what the letters spell, not whether the board has a
  numpad — and laid out on real keycap proportions, so the numpad's columns
  line up and the arrows form the usual inverted T. The numpad's `+` and
  `Enter` are one key two rows tall, as they are on the board beside you. The
  German layout's Enter stays two keys, because an ISO Enter is an L rather
  than a taller rectangle.
- **The on-screen keyboard lights up the key you press on the real one.** Hold a
  key and its twin on the OSK is highlighted for as long as you hold it, which
  is what makes the keyboard usable as a key tester or a screencast overlay
  rather than only as an input. It reads the keyboard device directly — the
  compositor never tells a window about keys aimed elsewhere — so three things
  are worth knowing: it runs **only while the on-screen keyboard is open** and
  is stopped the moment it closes, it knows key *positions* and not letters
  (nothing it handles can say what you typed), and it writes nothing down.
  Caps Lock and Num Lock show their **lock** rather than the press, so they
  stay lit while the lock is on.
  Turn it off with `osk.showPhysicalKeys`. On a machine whose user cannot read
  input devices it simply does not highlight, and asks for nothing.

### Fixed
- **The on-screen keyboard and the wallpaper selector stop frosting their own
  shadow.** Both were still asking the compositor to blur their whole surface,
  which takes the drop shadow with it — so what should have been a shadow under
  the panel read as a smudge. They now blur only the panel body, the way the
  bars, the dock, the OSDs, the overview, the cheatsheet and the notification
  popups already do.
- **The Menu key does something.** It was sending an evdev code that nothing
  in a normal session listens to, in every layout, silently.
- **A key's label no longer paints over the keys either side of it.** Longer
  labels shrink to fit their cap instead.

## [0.28.0] — 2026-08-20

Desktop widgets can be moved from the keyboard, and an undo that reversed a
multi-step gesture stopped landing halfway through it.

### Added
- **Arrow keys move a selected desktop widget.** Click a widget — or drag a
  marquee over several — and each arrow press moves the selection one grid
  cell, on the plain desktop as well as in Edit Mode. A widget sitting off the
  grid is put back on it by the first press, so a widget placed by keyboard
  ends up on the same lattice as one placed by mouse, and a group travels as a
  block, stopping when its first member reaches the screen edge rather than
  spreading out against it. Holding a key down is one undo, not fifty.

### Fixed
- **Undoing a multi-step gesture no longer stops halfway.** A gesture that
  moved one widget several times in a row undid to the second-to-last step
  instead of the start, because the steps were replayed in the order they were
  made. Group drags were never affected.

## [0.27.0] — 2026-08-19

The shell's motion catches up with itself: bar widgets travel instead of
teleporting, popups unroll out of what they are about to show, and the speed
slider finally reaches every animation there is. Clock depth learns live
wallpapers, the weather popup grows an hourly forecast, and your phone stops
being ten seconds behind.

### Added
- **Bar widgets slide to their new place instead of teleporting.** When the
  system tray empties, a plugin's bar widget is switched off, or the layouts
  are reordered, every widget after it used to be drawn somewhere else on the
  very next frame. They now travel there. Both bars, every corner style, and
  the widget that returns still appears where it belongs rather than flying in
  from wherever it last sat; a reorder drag in Edit Mode is left alone while it
  is in flight.
- **Long names scroll instead of being cut off.** Four places showed a name you
  did not write and cannot look up anywhere else on the row, and cut it off with
  an ellipsis: the dock's window preview — where the title is the only thing
  telling several windows of one application apart — and the Wi-Fi network,
  Bluetooth device and audio stream lists in the right sidebar. Those now scroll
  to the end of the text and back whenever it does not fit, so a router that
  names its two bands and its guest network off one prefix stops producing rows
  that read identically. Everything the shell wrote itself — status lines,
  buttons, settings captions — still elides. The scroll stops the moment the
  panel it is on closes, its speed follows the motion speed setting, and with
  reduce motion on it holds each end for three seconds and switches between them
  rather than scrolling, so the whole name is still readable.
- **The bar's weather popup has an hourly forecast.** Five three-hourly slots
  under the current conditions, each a bar grown from the axis with its
  temperature above it and its own condition glyph and hour below — night-aware
  on the hour it describes rather than on the time you opened the popup, and
  labelled with the weekday where the window crosses midnight. It follows the
  clock format you already set, and it costs no extra request: both providers
  were already returning this data in responses the shell fetches. A provider
  that answers with nothing hourly leaves no empty row behind.
- **Clock depth works on a live Wallpaper Engine scene.** The depth picker
  segments the still the shell already photographs of the active project, keyed
  on the project rather than on the still (which is re-grabbed every session),
  and the desktop layer masks the *live* surface with it — the silhouette stays
  put while the pixels inside it keep moving. The picker says so, and says when
  a project has not drawn its first frame yet. A mask cut from a still picture
  never lands on a live scene, and a project's mask never lands on the static
  fallback the desktop shows when the renderer gives up.

### Changed
- **Your phone's battery and connection state update the moment they change.**
  The phone panel and its quick toggle used to redraw on a timer, so a phone
  going out of range, coming back, or charging showed up in the shell up to ten
  seconds late. With KDE Connect the shell now listens to the daemon instead of
  asking it, and the change appears as it happens. Valent still updates on the
  timer, unchanged: its signals could not be checked against a running Valent
  daemon, and guessing at them would have been worse than the wait. If the
  listener cannot stay up, the shell quietly goes back to asking on a timer
  rather than showing nothing.
- **Dragging a quick toggle moves it instead of redrawing the grid.** The tiles
  the dragged one passes now slide into their new places when you drop it,
  rather than the whole panel being rebuilt at the new order. Nothing about the
  layout, the sizes or where a drop lands has changed — and a row now fills the
  panel's width evenly instead of giving the leftover to whichever toggle
  happened to be first in it.
- **A bar popup unrolls out of its own first card.** Hovering a bar widget used
  to grow a card from a dot into its full height; it now appears already the
  height of the first thing inside it — the weather hero, the calendar's month
  header — and unfurls to reveal the rest, with the fade riding the same
  motion. The top edge never moves, so what you came to read is legible on the
  frame the popup appears rather than once it settles. On a bottom or a side
  bar it is the bar-adjacent edge that stays put, and it stays put exactly, on
  every frame of the open and the close.

### Fixed
- **Spinners and pulses stop when nothing can see them.** Seven animations
  looped forever regardless of whether the thing they animate was on screen —
  the bar's update spinner turned for the whole session whether or not it was
  shown, and the world map's location ping ran on a settings page that spends
  most of its life closed. Each one keeps the compositor repainting the whole
  screen while it runs, which is what halved a fullscreen game's frame rate
  once already.
- **The motion speed slider and reduce motion now reach every animation.** Nine
  places read a motion tier's base duration instead of the scaled one, so they
  ignored both settings — the settings-page scroll settle and its rubber band,
  the navigation rail's tab highlight, the privacy popup's fade, the recording
  panel's pulse, and both shape-morph canvases. A shape morph could not be
  retimed at all.
- **Clock depth masks are crisp.** On wide wallpapers the subject's outline
  used to claim a soft band of background around fine structure like hair, and
  whatever was behind it showed through — a striped wall came through as
  subject. The producer now stores the mask aspect-true at 4096 on the long
  side instead of a 1024 square and hardens the edge around the model's own
  boundary at that size, so the outline is about a pixel wide instead of a
  five-pixel ramp. Same cost per run; re-run a wallpaper's models in the depth
  picker to get the new mask.
- **Windows now follow the auto-hidden bar instead of jumping.** The bar has
  always slid in and out over ~200ms while the space it reserves changed in one
  step, so everything behind it snapped a whole bar height at one end of the
  gesture. The reserved space is animated on the same curve as the bar now, on
  both the horizontal and the vertical bar. Nothing about where the bar sits at
  rest changes.

## [0.26.0] — 2026-08-19

The lock screen gets its own widget layout, snapping stops gluing widgets
together, and two things that could not be stopped or found their place now
can.

### Added
- **The lock screen's widget layout is its own.** Move a widget on Edit Mode's
  Lockscreen tab and that screen forks: from then on the lock and the desktop
  arrange — and size — their widgets independently, so the media widget can be
  3×2 on the desktop and 1×2 on the lock. Nothing changes until you move
  something; a screen you have never edited there keeps following the desktop,
  and the drawer's Lock section says which state you are in and offers **Use
  desktop layout** to re-link. Undo works across tabs, and presets carry both
  layouts — a preset from an older shell leaves your fork alone.
- **An edge-snapping toggle on Edit Mode's toolbar**, beside "Add widgets". It
  is the same switch Settings already offers, surfaced where the snapping
  happens.

### Fixed
- **Widgets snapped side by side keep one gap between them** — the same 12px
  that already separates the cells inside a wider widget — instead of gluing
  into a slab. Aligning an edge to an edge still lands exactly on the line.
- **A recording you cannot stop.** Every stop path sends the recorder one
  SIGINT, and a background job in a non-interactive shell is born ignoring it;
  the recorder normally undoes that once capturing, but one stuck before its
  first frame never did. The stop now escalates INT → TERM → KILL, the launch
  no longer hands the recorder an ignored INT, and a recording that produces
  no frames within 25 seconds is torn down and reported instead of sitting
  behind an indicator that says "recording". (The underlying cause on the
  reporting machine was a hung `xdg-desktop-portal-hyprland`; fullscreen
  recordings go through the portal, region recordings do not, which is why
  only one of them appeared broken.)
- **A bar popup that opened in the top-left corner** rather than under its
  widget. The popup surface now unmaps while idle (0.25.0's fullscreen frame
  fix), and a layer surface that has just been shown reports a placeholder
  size for its first tick — the card was being clamped against 500×500. It
  places itself again once its real geometry arrives.

## [0.25.0] — 2026-08-18

The Edit Mode release. Press the button and the desktop shrinks into a card
lifted off the wallpaper, and everything the shell normally hides comes out:
drag widgets, drop new ones from a drawer, right-click one for its size, arrange
the bar and the dock in place at full size, and lay out the lock screen from a
preview that cannot authenticate. Undo is Ctrl+Z. Done puts it all back.

Also in here: a fullscreen game gets its frames back, the wallpaper's subject
can stand in front of the clock, and the OLED screensaver has a key.

### Added
- **Edit Mode.** One mode, four in-place editors, on one clock. The desktop
  shrinks about its own centre into a card with a shadow and a glass edge; the
  bar and the dock stay at full size and are edited where they are, with visible
  bucket boundaries and remove badges; the Lockscreen tab filters the same
  viewport into what the lock will show — its wallpaper, its palette, its
  widgets, its islands — through a preview context that constructs no
  authenticator by contract. A drawer catalogues every widget the shell can add
  and drops it where you let go of it. Right-click a widget for Remove, Pin and a
  Size stepper. A dragged widget holds a neighbour's edge through hysteresis
  rather than snapping and unsnapping on the boundary. Ctrl+Z walks the whole
  edit back, Ctrl+Shift+Z forward. The grid appears when you start dragging, not
  when you enter the mode.
- **The lock screen's islands reorder.** Drag the pieces of each island into the
  order you want; the password field is the one that will not move. A list
  written by a newer shell loses nothing when an older one reads it back.
- **Clock depth.** The wallpaper's subject drawn over the desktop widgets, so
  the clock sits behind the person or object in the picture. Off by default,
  per-wallpaper, and accepted once by you rather than judged automatically — the
  detectors' confidence numbers do not rank cutout quality, and this ships as a
  verdict you give. Where the detectors find no subject at all (half of one real
  library), click the subject yourself, on the desktop at full size, over the
  real widgets, with undo — a thumbnail was too small to aim at a shoulder.
- **The OLED screensaver has a key** (`CTRL+SUPER+L`), blanks the focused
  monitor rather than the one under the cursor, and holds an idle inhibitor for
  a screen you blanked on purpose so it never walks the session into a lock.
- **Region capture grew a toolbar.** Shot/Record and full-screen in the overlay
  itself, a loupe at the cursor while framing, and — while a region records —
  stop, pause and save-clip beside the rectangle. The toolbar is never placed
  inside the region, because it would be in every frame of a clip that cannot
  be retaken.
- **The privacy pill acts.** Click it for a card that mutes a stream, or ends
  the capture, scoped to one app; hover still reads.
- **A real XDG sound-theme engine.** System sounds resolve through the installed
  theme and its `Inherits=` chain and play once, in place of two hand-built
  paths and an `ffplay` at each, one of them always doomed.
- **Launcher apps rank by how often you launch them.**
- **An animation multiplier with a named reduce-motion floor**, one stagger
  policy for every list, and content that swaps only after the shape it lives
  in has finished moving. About 700 call sites take it without changing.
- **Widget behaviour is a toggle bar**, not six switch rows.

### Fixed
- **A fullscreen game no longer loses half its frames to the shell.** One
  infinite rotation — the cookie clock's dial, thirty seconds per turn — kept
  the whole 5120×1440 output repainting behind an opaque game, because a running
  animation is a scene the compositor must redraw every frame whether or not
  anyone can see it. Measured against the game's own counter: 52 fps with the
  shell running, 108 with it stopped; 92 against a 94 ceiling after. Every
  looping animation now stops when what it animates is off screen, the bar's
  hover-card surface unmaps when it has nothing to show, and the Activate Linux
  watermark stands down under a fullscreen window — a 340×120 Overlay surface
  was the last thing holding the compositor's fullscreen fast path shut. The
  background surface stays mapped on purpose: destroying it is what once left
  Wallpaper Engine strobing at 30 Hz.
- **The launcher stopped spawning a calculator per keystroke** — eight
  processes for the word "firefox".
- **The updater no longer destroys local work** in the suite checkout: a
  hard reset to the fetched head is now a rescue branch, a stash and a log.
- **The vertical bar renders plugin bar widgets** instead of an empty stub.
- **Four binding loops**, each the same shape: a property that read the thing
  it drove.
- **The dock's turn is a size, not a different set of anchors**, so switching
  edges no longer resizes it from its parent.
- **A settings deep link finds its page by id**, not by the page's translated
  name.
- **The anti-flashbang's weak rung has the shader it always named.**
- **A tray menu opened from a bar hover card is blurred**, and the card's
  translucent shadow is not.
- **Two easing bugs.** The bar's util button and every resize grip had run on
  `Easing.Linear` since they were written, from naming a motion tier's duration
  and dropping its curve; a check now fails on a new one and holds the 40
  existing partial takes as a ratchet.

### Changed
- **The shell's own test harnesses run on a private session bus.** One of them
  read the developer's browser as a media player, which hides two lock-screen
  slots, and failed on one machine while passing on every other with the code
  identical. New harnesses must decide their bus; the 33 existing ones are a
  register.
- Reordering a widget moves it rather than swapping it with the neighbour it
  lands on, at every call site.
- The three shape tokens the design system reads are declared once.

## [0.24.0] — 2026-08-13

The Material 3 Expressive morphing release: desktop widgets stopped disappearing
when they resize. Every shared element of a widget is now declared once and
travels between the places its spans put it, on one clock, over a card that
bows when you pull it and casts a shadow that lifts when you handle it.

### Added
- **Widgets morph instead of swapping.** A widget used to hold one layout per
  span and cross-fade between them, so its own parts vanished and reappeared on
  a resize. Media, weather and currency are each one tree now: the play button,
  the seek bar, the glyph, the rates panel are single elements whose geometry
  comes from a per-span table, and the resize animates them from one place to
  the other. Only what genuinely has no home at the next span fades.
- **Elastic resize.** A widget's card resists the pull, bows at the edge you are
  dragging, and breaks to the next span when you pass the threshold — with the
  constants tuned on screen rather than guessed, and expressed as time so they
  do not change with the frame rate.
- **Desktop cards cast a shadow**, lifting on hover and further while dragged.
  The five older bundled widgets that carried their own hand-rolled shadow at
  their own values now share the one elevation, and calendar — the copy the
  design spec recorded as having already drifted — draws on the shared card.
- **One interaction model** for hover and press, in `Appearance`, adopted by
  both RippleButtons and the media transport controls. A press is acknowledged
  faster than it is released, and a release animates even when the pointer has
  already left the control.
- **The dock lives on any edge.** Top is a mirror of bottom; left and right are
  a genuinely different layout, ported from the vertical dock strip the shell
  already shipped in its bar. One derivation decides anchors, thickness, the
  reserved zone and the margin pair for all four. The settings UI declines to
  put the dock on an edge an auto-hiding bar already owns.
- **A weather forecast on the desktop.** The weather card gains a 3x2 span whose
  second row is the day-by-day outlook, from either provider, and a background
  line tracing today's daylight with the sun's position on it.
- **A media widget at three sizes**, whose play button *is* the visualiser and
  whose seek bar bends from a straight line to a ring inside the button to the
  button's own outline.

### Fixed
- **Screen recordings were washed out.** The tonemap assumed a signal peak of
  ten times reference white; a desktop capture peaks near one. Measured from the
  pixels instead, white lands at 210/255 rather than 136.
- **Only the first notification of a session was blurred.** The popup refreshed
  its blur region from a signal that never fired again, so from the second
  notification on the compositor was handed the region of a destroyed card.
- **The currency widget stopped saying "Network timeout" forever.** It made one
  attempt per session; it now walks both hosts and retries with backoff.
- **A paused player no longer repaints an invisible bar visualiser at 237 fps.**
- **Weather icons match the provider that reported them.** Both providers' codes
  were resolved through one provider's table, drawing a clear sky through every
  storm on the default provider.

### Changed
- The morphing machinery is shared rather than copied: one module for the shape
  morphs, one spelling of the travel animation, one card component. Checks fail
  on a fourth copy rather than a note asking for one.

## [0.23.1] — 2026-08-10

### Fixed
- **Right-clicking a tray icon in the overflow popup crashed the whole shell.**
  0.23.0 moved every bar popup's content onto one shared card, and a tray menu
  is a window opened from that content - so closing the popup unparented the
  content while the menu was still anchored to the window it had been in. Two
  smaller faults from the same move went with it: the overflow closed itself the
  moment a menu opened, and the menu closed itself again about half a second
  later.
- **A tray menu opened from the bar is blurred again.** Menus inherit the blur
  rules of whichever surface they were opened from, and moving tray items onto
  the shared card quietly moved them onto a surface whose threshold no
  translucent menu could reach.
- **The cheatsheet no longer runs off the sides of a smaller screen.** The
  column count was decided by how much *height* there was, and columns trade
  height for width - so a display with room to spare vertically but not
  horizontally was given four columns and the outer two were cut off at the
  screen edges.
- **An auto-hidden bar comes back when you throw the pointer at the screen
  edge.** With the detached bar style the bar's surface was held a few pixels
  off the edge, and those pixels belonged to no part of the bar - so the edge
  itself did nothing, and hiding left the band above the bar untouched instead
  of clearing it. Sliding along the top edge no longer makes the bar flicker in
  and out either.

## [0.23.0] — 2026-08-10

### Added
- **The cheatsheet lists every keybind, in columns.** It used to draw only the
  groups that had sub-groups, silently dropping 28 of the 61 binds on this
  machine's config, and stacked what was left into one tall column beside an
  empty screen. Click any shortcut to reassign it: the editor warns before
  taking a chord that is already in use, and closes itself after five seconds if
  you opened it by accident.
- Chords are drawn as one keycap per key, so `SUPER SHIFT ALT R` reads as four
  keys held together rather than one key with a long name. Existing configs are
  migrated once, since the old value was the shipped default and there is no
  setting for it to have been chosen from.
- **Bar popups are one card that moves.** Hovering from the clock to the weather
  used to destroy one popup and reveal another, with nothing connecting them —
  eleven separate surfaces, eleven shadows, eleven compositor animations. There
  is now a single card that travels and resizes along the bar while its contents
  cross-fade, and shrinks back toward the widget it belonged to on the way out.
  Clicking a widget that stays open — the tray overflow, Docker, Discord voice —
  parks the card there and holds it until you dismiss it; while it is held,
  hovering another widget deliberately does nothing.
- **The desktop right-click menu shows the colour schemes as colours.** Each of
  the nine scheme presets draws the palette it actually produces, instead of an
  icon that read as an animation. The wallpaper transitions submenu now offers
  every transition except the one already running.
- Desktop widgets can be excused from going opaque. A per-widget **Stay
  translucent** switch keeps a widget see-through when you turn transparency off
  for everything else, and keeps its frost with it.

### Fixed
- **Drop shadows are no longer frosted by the compositor's blur.** The
  cheatsheet, notification popups, the desktop right-click menu and the tray
  menu all drew a shadow that the whole-surface blur smeared into a band along
  their edge — on the cheatsheet this read as having no shadow at all. Each now
  scopes its blur to the painted body. Notification cards are handled one card
  at a time so the gaps between them stay sharp. Popups — the tray menu, the
  dock's context menu, the drag-apps sheet — cannot scope their blur that way at
  all, so they threshold it by alpha instead, at a point the shell works out
  from your transparency and bar-opacity settings and keeps up to date as you
  change them.
- **Panels no longer flash unblurred as they open.** Anything that opens on
  demand — the overview, the search bar, the sidebars, the OSDs — showed about
  a tenth of a second of sharp wallpaper before its blur arrived, because the
  blur region was only published on a settle timer.
- The desktop right-click menu and its submenu gained a card to sit on, which is
  what lets them carry a shadow at all.
- **Turning transparency off now actually makes things opaque.** The switch
  removed every desktop widget's blur while their panel alpha carried on coming
  from settings that ignored it — so fourteen widgets sat at roughly a tenth
  opacity over a newly *sharp* wallpaper, which looked worse than leaving
  transparency on. The bar's own opacity and the drop shelf ignored the switch
  the same way; the shelf shipped 50% see-through with transparency off, in the
  default config. Settings rows that govern nothing while the switch is off are
  greyed out rather than left live.
- **The Settings window keeps its frost when you toggle transparency off and back
  on.** It used to come back translucent but unblurred and stay that way until
  the shell was reloaded, because a window whose clear colour reaches full opacity
  even once tells the compositor it is opaque and never takes that back.
- **Desktop widget frost comes back all at once.** After anything that rebuilt it
  — the transparency toggle is the easy one — widgets re-frosted one at a time,
  about 0.6s apart, taking some 3.6 seconds to finish on eight widgets. Each
  widget was decoding its own private copy of the same wallpaper, twice, and they
  queued; they now share one decode. Dragging a frosted widget no longer
  re-decodes the wallpaper on every pixel of travel either.
- A disabled switch in Settings dimmed twice, once for the row and once for
  itself, so it read as darker than the rest of the disabled row.

### Changed
- **The login greeter no longer refreshes through root.** The SDDM theme pin
  moves to imi-sddm-theme v0.3.1, which publishes the greeter's colours,
  settings and wallpaper into a staging directory owned by you and readable by
  the `sddm` group, reached from the installed theme through symlinks. Every
  wallpaper switch used to end in a root script that parsed your config and ran
  **ffmpeg as root over your wallpaper video**; none of that escalates now, and
  the passwordless sudo rule it needed is removed on the next install.
- Existing installs migrate in place on Update Dots, seeded from the greeter
  currently on screen so nothing about it visibly changes.

## [0.22.0] — 2026-08-09

### Added
- **Wallpaper parallax is back, and it works with live wallpapers too.** The
  wallpaper drifts as you move between workspaces, nudges when a sidebar opens,
  and the desktop widgets travel a little further than it does so they read as
  sitting in front of it. Portrait wallpapers pan down instead of across, and
  vertical panning can be forced for any wallpaper. Wallpaper Engine projects
  parallax exactly like stills, cross-fades included. Controls live under
  Settings → Desktop → Parallax; the zoom there is the room the effect has to
  move in.
- Existing configs are migrated once: the knobs had been carried since
  dots-hyprland with nothing reading them, so whatever they held was a leftover
  rather than a preference and would have left the revived effect switched off.

## [0.21.0] — 2026-08-09

### Added
- **Launch Minecraft modpacks from the search bar.** Press Super, type a pack
  name and hit Enter: Prism Launcher instances now appear in the launcher
  results alongside apps, each with its own pack icon, Minecraft version and
  mod loader. A `%` prefix lists every instance for browsing, configurable
  under Settings → Services → Prefixes. Feature-detected end to end — on a
  machine without Prism Launcher nothing runs, the prefix stays an ordinary
  character, and the settings row is hidden.

## [0.20.1] — 2026-08-08

### Fixed
- **The Wallpaper Engine prebuilt survives Arch's ffmpeg 9 upgrade.** The
  installer pin moves to qs-wallpaperengine v0.2.5, a rebuild-only release
  against the ffmpeg 9 sonames. The v0.2.4 prebuilt's
  `liblinux-wallpaperengine-lib.so` links the ffmpeg 8 libraries
  (`libavcodec.so.62` et al.) that the `2:9.0` soname bump removes, and it is
  a load-time dependency of the WE-capable quickshell — so after a system
  update the shell failed to start at all with `libavcodec.so.62: cannot open
  shared object file`.
- **tmux is now a component in the installer's interactive menus.**
  `--skip-tmux` existed only at flag level, so the TUIs — which is what
  Update Dots actually runs — installed the tmux dots on every run with no
  way to decline. Both front-ends now list a tmux toggle; it pre-selects when
  the deployed `tmux.conf` is ours (detected by its matugen source line) or
  when none exists, and defaults to unticked over a foreign `tmux.conf` so an
  update never clobbers a user's own setup with the step's `rsync --delete`.
- **The fzf installer menu keeps the cursor on the toggled row for real.**
  The earlier fix bound `pos()` to fzf's `start` event, which fires before
  the piped-in menu items are read — it no-op'd on an empty list and the
  cursor still snapped to the top, timing-dependent. Rebound to `load`, which
  fires once the input is complete (measured: `start:pos(3)` lands on row 1,
  `load:pos(3)` on row 3).

## [0.20.0] — 2026-08-07

### Added
- **Keyboard shortcuts are editable from the shell.** Every keybind row in the
  cheatsheet (Super+/) gains a hover pencil that opens an editor: capture a new
  chord, remove the binding, or reset it to default, with conflicts against
  every statically known chord (submaps included) detected before anything is
  written. A new Keybinds section on the Hyprland settings page lists the
  current overrides, resets them per-row or all at once, and adds brand-new
  command shortcuts. Changes live in a shell-owned sidecar rendered into
  `hypr/hyprland/shellOverrides/keybinds.lua` — the shipped keybinds and
  `hypr/custom/keybinds.lua` are never touched, the generated file survives
  dots updates, and a hand-edited override file is detected and left alone.

## [0.19.0] — 2026-08-07

### Added
- **tmux ships with the dots, styled like the suite's terminal.** A new
  `~/.config/tmux/tmux.conf` (C-Space prefix, vim-style pane navigation,
  vi copy mode, cwd-preserving splits) starts **fish** by default (guarded, so
  a fishless machine falls back to the login shell), and the status line is
  drawn as floating Material pills — rounded Nerd Font caps on a transparent
  bar — with every color coming from the active matugen palette, regenerated
  on each wallpaper/color switch. The install step is its own skippable unit
  (`--skip-tmux`, included in `--core`) and deliberately preserves
  `~/.config/tmux/plugins/` (tpm) and the palette-generated `matugen.conf` on
  every sync. The pill styling appears after the next wallpaper or palette
  switch regenerates the theme file.

## [0.18.2] — 2026-08-07

### Fixed
- **Video wallpapers no longer leak ~10 MB of memory per minute.** The shell
  grew by roughly 14 GB/day with any Wallpaper Engine *video* wallpaper active
  (scene wallpapers were fine) — an upstream mpv bug: its `vo=libmpv` render
  path creates one GL fence per rendered frame and never deletes it, and each
  one pins ~5 KB of driver memory for the life of the process
  ([qs-wallpaperengine#16](https://github.com/XephyLon/qs-wallpaperengine/issues/16)).
  The embedded engine is bumped to
  [qs-wallpaperengine v0.2.4](https://github.com/XephyLon/qs-wallpaperengine/releases/tag/v0.2.4),
  which caps the fences (measured: 10.2 MB/min → 0.6 MB/min, flat after
  warm-up) and also stops a needless per-frame PulseAudio enumeration when
  wallpaper audio is off. Run **Settings → Update Dots** and restart the shell
  to pick up the new prebuilt; an already-bloated shell only returns the
  memory on restart.

## [0.18.1] — 2026-08-06

### Fixed
- **The cursor theme picker no longer runs off the page.** 0.18.0 shipped it as a horizontal chip
  strip, which with fifteen installed themes overflowed the settings window and clipped its own
  label. It is now a wrapping card grid in the icon-pack style — and each card shows the theme's
  **actual pointer**, extracted from the theme's own Xcursor file by the scanner (the format is a
  simple container Qt can't read but a few lines of stdlib can; no new dependencies). Unparseable
  pointers fall back to an icon instead of failing.

## [0.18.0] — 2026-08-06

### Added
- **Cursor settings** (Settings → Cursor): theme (scanned from the system), size, zoom factor and
  inactive timeout. Applies system-wide — `hyprctl setcursor`, GTK 3/4, an `~/.icons/default`
  `Inherits` stub for XWayland clients — and startup now applies the *configured* cursor instead of
  a hardcoded `Bibata-Modern-Classic 24`.
- **Phone Connect**: paired-phone battery and actions (ring; ping/send-clipboard where the backend
  supports them) from **KDE Connect or Valent**, auto-detected over the session bus, surfaced as a
  sidebar quick-tile with a device dialog. No daemon = the tile stays hidden; pairing remains in the
  daemons' own UIs.
- **Clight integration**: when the `clight` daemon is running, the shell's brightness controls
  route through it so its next recalculation doesn't fight manual changes; daemon temperature
  changes get their own OSD readout (`4500K`). Night-light ownership deliberately stays with the
  built-in Hyprsunset path — Settings warns when both are active instead of silently picking one.
- **Multi-widget selection**: in widget edit mode, drag a marquee over desktop widgets and move
  them as a rigid group — lattice snapping, per-monitor persistence, Escape/click-away deselect.
- **SDR fullscreen recording is instant again**: the screen-share portal path returns, now on a
  proven footing — a shipped `~/.config/hypr/xdph.conf` (`allow_token_by_default = true`) makes the
  portal issue a restore token, so the picker appears once ever. The earlier removal misdiagnosed
  an empty token as an xdph limitation; it was an unchecked-by-default picker checkbox, and gsr's
  `()` log line was it echoing its own empty cache. Regions and replays keep the background GPU
  converter.

### Fixed
- **Every widget drag is now pixel-exact.** `MouseArea.drag` rebases its origin at grab and fought
  the position binding — a +96px gesture applied +168px, hidden for months behind the 12px lattice
  snap. The drag is now computed in the parent frame from the press point.
- **Plugin-manifest strings can no longer inject rich text**: `StyledText` defaults to plain text
  with reviewed opt-ins, pinned by a lint that also catches inline `textFormat` overrides;
  overlay-widget registry entries now require a screenshot.
- **Desktop right-click menu**: "Live Wallpaper" removed (duplicated the wallpaper selector);
  clicking "Wallpaper & style" or "Widgets" now opens the matching Settings page instead of doing
  nothing — hover submenus unchanged.

### Changed
- **`WE_REF` moved to qs-wallpaperengine v0.2.3** — the first prebuilt whose tarball ships correct
  RUNPATHs, making the installer's patchelf repair a belt-and-braces no-op.

## [0.17.6] — 2026-08-05

### Fixed
- **Fullscreen recording prompted the screen-share picker on every use with SDR recording on.**
  The 0.17.4 portal design assumed session restore would make the picker a one-time approval;
  `xdg-desktop-portal-hyprland` (1.4.1) returns an **empty** restore token, so restore is a no-op on
  this stack and the picker appeared every single time. Portal capture is removed entirely: every
  path records HDR via KMS with **zero prompts** (regions keep their single shell-selector pick),
  and the SDR switch — honestly named "Convert HDR recordings to SDR" again — delivers via the GPU
  converter a few seconds after each save. Guarded against regression: a test fails the suite on
  any portal reintroduction until a non-empty restore token demonstrably round-trips.

## [0.17.5] — 2026-08-05

### Fixed
- **Region recording prompted for a selection twice with SDR recording on.** The recorder overlay's
  "Record Region" runs the shell's own region selector — and 0.17.4 then routed the capture through
  the screen-share portal, whose picker asked again. Portal capture is now fullscreen-only, where
  its one-time remembered approval never interrupts a flow; regions always use the shell's selector
  (or slurp), record HDR via KMS, and convert to SDR on the GPU a few seconds after saving. One
  selection, everywhere. SDR-mode regions force an HDR capture codec even under an explicit H.264
  choice: the converter re-encodes to H.264 anyway, and honouring it at capture would bake the
  wash-out in first.

## [0.17.4] — 2026-08-05

### Changed
- **SDR recording on HDR displays is now instant instead of converted.** With "Record SDR on HDR
  displays" on (renamed from "Convert HDR recordings to SDR"), recordings capture through the
  screen-share portal, whose stream the compositor tonemaps — the same reason a screenshot of an
  HDR desktop looks right. Native SDR at capture time, no conversion wait at all, for **regions as
  well as fullscreen**: the portal picker's Region tab replaces the region selector, a fresh pick
  each time. Fullscreen shows the picker once and remembers the choice. Replays still record HDR
  and convert in the background.
- **The background converter is ~2.6× faster** (12.9s → 4.9s on an 8-second 5120×1440 clip): the
  GPU tonemap had silently never run — a `grep -q` under `pipefail` mis-read the ffmpeg filter
  probe as a failure from the converter's first version — and encoding now uses a tried-for-real
  GPU ladder (NVENC/VAAPI, CPU floor), switching to HEVC above 4096px width where NVENC's H.264
  hard-caps. The GPU chain is smoke-tested before being chosen, so machines without a Vulkan
  device keep the CPU path instead of failing outright.

## [0.17.3] — 2026-08-05

### Added
- **Optional SDR conversion for HDR recordings** (Settings → Capture → "Convert HDR recordings to
  SDR", default off). Recording an HDR display stores real HDR10 since 0.16.0 — correct in
  HDR-aware players, washed out in everything that cannot tonemap: VLC as Arch ships it (built
  without libplacebo, so no setting fixes it), Discord embeds, browsers, editors. With the switch
  on, every saved recording **and replay** is tonemapped to bt709 SDR in the background and
  replaced, with notifications at start and finish. A failed conversion keeps the HDR original and
  says so; already-SDR files are never touched, so double-tonemapping cannot happen. Measured at
  5120×1440: an 8-second clip converts in ~13 seconds. Off by default because a true HDR file is
  the better artifact when your players can handle it — this trades fidelity for universality,
  which is a choice, not a default.

## [0.17.2] — 2026-08-05

### Added
- **The login screen now follows the desktop reactively.** The SDDM greeter's inputs used to
  refresh only as a side effect of color generation, so a Wallpaper Engine scaling change never
  reached it, and the full-resolution still — grabbed a moment *after* the config change that
  announced it — could miss the login screen until the next unrelated color event. A new
  `GreeterSync` service observes the greeter-relevant settings directly and is poked when the still
  finishes writing, firing the SDDM theme's new gated sync entry point, which escalates to the
  privileged copy only when something the greeter consumes actually changed. A scaling change now
  reaches the login screen in seconds, with no wallpaper switch. Design study in
  `docs/superpowers/specs/2026-08-05-reactive-greeter-sync-design.md`.

### Changed
- **`SDDM_REF` moved to `imi-sddm-theme` v0.2.4** (`ed9ce03`): the greeter respects the fill / fit
  / stretch scaling choice (it hardcoded crop; the video poster frame was additionally distorted by
  a missing `fillMode`), and ships the gated sync wrapper above. The halves pair, but each is safe
  alone — the shell no-ops while the wrapper is absent, and the theme works from matugen's hook
  alone.

## [0.17.1] — 2026-08-05

### Changed
- **The greeter's still is grabbed off the live wallpaper surface instead of rendered by a second
  process.** 0.17.0 produced it by launching another `linux-wallpaperengine` — an entire extra copy
  of the renderer and libcef, several seconds of GPU, and a window that took focus while it worked —
  to photograph a frame the shell was already drawing, because Wallpaper Engine runs *inside* this
  shell's process. The still is now `grabToImage()` on that surface (the same grab the wallpaper
  transition already uses), saved losslessly as PNG at the display's own size. Instant, invisible,
  no subprocess. The render script, its queue and its cache are deleted rather than tuned.
- **`activeStill` is out of the config schema again, this time by design rather than neglect.** Its
  path is derived — `~/.cache/quickshell/wallpaperengine-stills/<activeProject>.png` — by every
  consumer, so it cannot disagree with the project the config names. Re-declaring the field in
  0.17.0 had silently re-armed the stale values still stored in saved presets
  ([#103](https://github.com/XephyLon/immaterial-impulse/issues/103)); removing it makes them
  unreachable again with no migration. `stop()` has nothing to clear — emptying `activeProject`
  stops the path resolving by itself.
- **`SDDM_REF` moved to `imi-sddm-theme` v0.2.3** (`797c1f4`), which derives that same path instead
  of reading the stored field. The halves ship together; either half alone falls back to the
  preview thumbnail.

### Added
- **Agent-doc governance.** `AGENT.md` and `CONTRIBUTING.md` are read sequentially in full before
  any work (rule mirrored in a new repo-root `CLAUDE.md`); every point added to them must cite the
  commit that motivated it (`tests/lint_doc_citations.py` fails the suite on citations resolving to
  nothing, by SHA or exact subject); every PR body must carry a `Docs:` receipt line (new
  `docs-receipt` workflow). Grown out of this release's own history: the 0.17.0 mechanism this
  release deletes was built without reading the issue that had already rejected it.

## [0.17.0] — 2026-08-05

### Added
- **The greeter now gets the wallpaper at the display's own resolution.** A
  Wallpaper Engine project ships exactly one image — the Steam Workshop preview,
  a thumbnail, often square and around 1000px — and that was the only thing the
  login screen could show. On a wide display it is cropped to a narrow band and
  upscaled several times over ([#113](https://github.com/XephyLon/immaterial-impulse/issues/113));
  measured here as a 910x910 preview stretched across 5120x1440.

  Applying a scene now renders a still of it through `linux-wallpaperengine`,
  sized to the focused monitor, and records the path as `activeStill` for the
  greeter to pick up. On this machine a scene lands at 5120x1440 in about three
  seconds for 1.8 MiB. Renders are queued rather than run concurrently — the
  renderer holds a GPU context — and only scenes are rendered: a video is a
  plain file the greeter can play or cut a frame from, and web wallpapers fall
  back to the static wallpaper everywhere. A failure is logged and nothing else:
  the greeter keeps the preview, which is what it had before, and a machine
  without the Wallpaper Engine extra never renders at all.

  `activeStill` was removed in [#103](https://github.com/XephyLon/immaterial-impulse/pull/103)
  for having no writer. It is back because it has one, and `stop()` clears it,
  so it can never name a project that is no longer active.

### Changed
- **`SDDM_REF` moved to `imi-sddm-theme` v0.2.2** (`29f3c88`), which reads
  `activeStill` and cuts a frame from an oversized video instead of falling back
  to the thumbnail. Nothing above reaches the login screen until this pin moves,
  so the two ship together.

## [0.16.1] — 2026-08-05

### Fixed
- **The library-path repair in 0.16.0 was incomplete.** It made the Wallpaper
  Engine binary's own library path correct, and the shell still could not start
  without help — so the wrapper kept exporting `LD_LIBRARY_PATH`, the very thing
  the repair exists to remove. `DT_RUNPATH` is not transitive: the executable's
  path resolves its own direct dependencies and nothing beyond them, while the
  bundled `liblinux-wallpaperengine-lib.so` looks up *its* dependencies through
  its own path — which was also the build machine's. `libcef.so` sat in the same
  directory and was still reported missing.

  `LD_LIBRARY_PATH` is transitive, which is exactly why the fallback worked
  where the repair did not, and why this went unnoticed: the fallback was
  quietly covering for it while being the leak it was meant to avoid. Every
  bundled library that cannot resolve itself is now repaired too.

## [0.16.0] — 2026-08-04

### Fixed
- **Screen recordings on an HDR display were washed out.** `gpu-screen-recorder`
  does not tonemap: handed an HDR surface with an SDR codec it encodes 8-bit and
  labels the file bt709, so a PQ signal is decoded as if it were gamma — flat,
  grey and desaturated. Nothing ever selected an HDR codec, and the Settings
  list offers only H.264/HEVC/AV1, so there was no way to get a correct
  recording at all. Recording an HDR monitor now picks the HDR variant
  automatically: HEVC and AV1 become their `_hdr` forms. H.264 cannot carry HDR,
  so choosing it explicitly is respected and explained rather than overridden.
  Applies to instant replay as well as one-shot recordings.
- **The installer could never repair the Wallpaper Engine binary's library
  path.** `patchelf` rewrites in place and the kernel refuses to write to a
  running executable — and the binary being repaired is the shell itself, while
  Settings → Update Dots runs the installer *from* the shell. So on the only
  path anyone takes, it always failed, silently, and then advised installing
  `patchelf` on machines that already had it. Only a first install, with nothing
  running yet, ever succeeded: the repair worked exactly when it was not needed.
  It now patches a copy and renames it into place, which the running process is
  unaffected by, and reports the real reason when something does go wrong.

  This was the mechanism behind the `LD_LIBRARY_PATH` fallback, which leaks
  CEF's bundled `libEGL`/`libGLESv2` into every application launched from the
  shell — the cause of graphics failures that look like driver problems.
- **`SDDM_REF` only pinned the installer, not the theme.** The pin selected
  which `setup.sh` was fetched; that script then cloned the theme itself from
  whatever the satellite's default branch happened to be, so an unmoved pin
  still installed today's theme and nothing reported the discrepancy. The pin is
  now passed through, so the installer and what it installs are one revision.

### Changed
- Pins imi-sddm-theme **v0.2.1**, the first revision that honours the
  pass-through above.

## [0.15.0] — 2026-08-04

### Fixed
- **"Reboot Into" armed your firmware and then never rebooted.** Picking another
  OS prompted for a password, succeeded, and did nothing visible — while leaving
  `BootNext` set, so some unrelated restart days later would boot the other OS
  with no warning. The handler called `Session.reboot()` without importing the
  module that declares `Session`; QML imports are not transitive, so the call
  threw and stopped the handler dead, and the "something failed" notification
  only covered a *non-zero* exit while this path exited zero. The reboot is now
  owned directly so its exit code is observable, and a reboot that fails clears
  the `BootNext` it just armed — or, if even that fails, tells you which entry
  will boot and the exact command to undo it.
- **Greeter colours stopped regenerating after every update.** The dots sync
  replaces `matugen/config.toml`, wiping the block the SDDM theme appends to it,
  and the code meant to put it back restored only the hook — not the template
  that generates the file the hook publishes. So the hook fired after *every*
  matugen run, dragging a `sudo` call with it, and produced nothing. Worse, it
  had been silently dead for a while: it keyed off a file that moved when the
  apply script became root-owned, so on any current install it never ran at all.
  The whole block is now restored, in the shape the theme's own installer writes.
- **Uninstalling ImI could delete an SDDM theme ImI never installed.** Step 5
  fired on a directory *name*, and `ii-sddm-theme` is also upstream's name — so
  anyone who installed the upstream theme themselves and then installed ImI
  without the SDDM extra lost their theme, config, fonts and sudoers rule to an
  ImI uninstall. Losing that directory while SDDM still names it is the case that
  costs you a login screen. Ownership is now proven by a marker written on a
  successful hand-off, and an unowned pre-fork install is reported, never deleted.
- **The bar sat 5px off the screen edge instead of 1px over it.** `||` binds
  tighter than `?:`, so the dead-pixel workaround's `-1` was swallowed as a
  ternary *condition* and every style came out `+5` — pushing the bar away from
  the edge it was meant to overhang, and making Hyprland reserve the space too.
- **Standalone bar badges (timer, privacy, submap) sat off-centre under Hug.**
  They centre in the whole bar, which only matches the group pill they sit in
  while its two margins are equal — and Hug drops its edge-side one, leaving each
  badge flush against one edge of its pill with all the slack on the other.
- **A failed Wallpaper Engine project hid the static fallback for ~9 seconds.**
  The transition overlay waits for a first frame from the new surface; a project
  the renderer gives up on never produces one, so a frozen still of the wallpaper
  you just switched *away from* stayed painted over the fallback for the
  watchdog's full budget. It now settles as soon as the project fails.
- **Un-suppressing could restore a Wallpaper Engine project you had moved off.**
  A switch requested while the wallpaper was covered was stashed for later, but
  nothing invalidated that stash, so a superseded project could come back
  silently while your config said otherwise.
- **The empty-notification placeholder overflowed a cramped list**, showing a
  shape with no room for it.
- **The Wallpaper Engine installer rebuilt from scratch on every update.** The
  "already up to date" check read a three-field stamp into two variables, so the
  recorded binary path was never a path and the skip could never fire — meaning
  every re-run paid the full fetch-and-build the stamp exists to avoid, up to 40
  minutes, even for updates that did not move the pinned revision.

### Changed
- Reboot, power off and firmware-restart now issue the transition *before*
  closing your windows. Previously a transition that failed — a denied
  authorisation, an inhibitor — had already killed every application first,
  leaving an empty desktop, still logged in, with nothing explaining why.
- Pins imi-sddm-theme **v0.2.0**, which fixes `check.sh` reporting FAIL on a
  correct install and teaches it to detect the failures it previously could not
  see (colours that never reached the greeter, a config outranking ours, an
  apply script whose path makes its sudoers rule an escalation).

### Added
- `test_wallpaperengine_prebuilt.py` now actually executes. It was written for
  pytest and invoked as a plain script, so for its whole life it defined seven
  test functions, called none of them, and reported success — which is how the
  rebuild bug above survived. Making it run surfaced that bug immediately.
- The QML import lint now covers every singleton, not just `Appearance`, and
  scans `services/` as well as `modules/` — the two gaps that let the "Reboot
  Into" defect through.

## [0.14.9] — 2026-08-04

### Fixed
- **Preset thumbnails showed the wrong wallpaper, and so did the login screen.**
  Both read a config field that nothing has written since July: the refactor that
  reduced Wallpaper Engine to a selector removed the code that rendered those
  stills, but left the field and its readers behind. It stayed frozen at whichever
  project was active that day — and because applying a preset restores your whole
  config, the stale value spread to every preset saved since and came back each
  time one was applied. Several preset cards therefore rendered the *same* image
  as each other, and the greeter served a months-old wallpaper indefinitely.

  Both now read the project's own preview, which is written on every wallpaper
  switch and always matches the active project. Presets already on disk keep the
  dead key — it is inert now that nothing reads it — and their cards are correct
  immediately. Pins imi-sddm-theme v0.1.1 for the greeter half.

  One trade-off: a *scene* wallpaper has no full-resolution still, so the login
  background is now a preview-sized image rather than a full render. Restoring
  proper still generation is tracked in #103.

## [0.14.8] — 2026-08-04

### Security
- **The SDDM theme no longer grants passwordless root on a file you can
  rewrite.** Its matugen integration installs a sudoers rule for the script that
  applies your colours to the login screen, and that script lived in your own
  home directory. `sudo` matches a rule by *path*, not by owner — so anything
  running as you could replace that script and run it as root with no password.
  It is now installed root-owned outside `$HOME`, and the installer refuses to
  write the rule at all unless the target and every parent directory is
  root-owned and not group- or world-writable.

  **If you have ever installed the SDDM theme, the old rule is still on your
  system.** Installing this version replaces it, but until then
  `/etc/sudoers.d/sddm-theme-<user>` still names the old path — `sudo -l` will
  show it. Pins imi-sddm-theme v0.1.0, which also fixes the theme never actually
  applying your wallpaper or colours, an uninstall that left SDDM pointing at a
  deleted theme (a login loop after a correct password), and a config drop-in
  that silently lost to KDE's.

### Fixed
- `repo-status` could report a stale pin as current. It compared against
  whatever the local clone had last fetched, so a satellite that had moved on
  looked up to date until someone remembered to fetch. It now asks GitHub for
  the tip directly, tells "no release published" apart from "could not reach
  GitHub", and no longer claims to be read-only while touching the git index.
- The background suppression tests could not see a regression written as an
  imperative assignment — the exact shape of the bug they exist to prevent,
  which strobes the display on every fullscreen toggle. They also went red when
  an unrelated comment was added nearby. They now parse the QML structurally
  rather than matching text, so they catch every route to that property and are
  indifferent to comments and indentation.

## [0.14.7] — 2026-08-04

### Changed
- **The shell now decides when a live wallpaper idles, per monitor.** Until now
  that call belonged to the embedded Wallpaper Engine, whose fullscreen detector
  turned out to be blind to outputs entirely — it counts every fullscreen window
  on the machine through a single counter, while the shell runs one renderer per
  monitor. A game fullscreened on one screen therefore froze the wallpapers on
  all of them, and no setting of that detector could fix it, because the problem
  was never which windows it counted. The shell knows which monitor is covered,
  so it now tells the renderer directly. Pins `qs-wallpaperengine` v0.2.2.

  Measured on a scene wallpaper: covering the output takes the renderer from
  about 9% of a core to about 1%, and uncovering it recovers within a frame or
  two. It does **not** stop a *video* wallpaper decoding — that is inside
  Wallpaper Engine and cannot be reached from here — so the saving is real for
  scene wallpapers and close to nothing for video ones.

### Fixed
- Two rendering faults in the embedded renderer, both silent when they struck. A
  frame-completion wait could name a fence that had already been deleted, which
  is not a wait at all — a torn wallpaper frame with nothing in any log to
  explain it. And switching wallpapers could leave the old frame's scene-graph
  node pointing at a texture that had been freed, so the next thing to claim that
  texture slot got drawn in the wallpaper's place — the "a widget's cached layer
  is suddenly fullscreen" symptom.

## [0.14.6] — 2026-08-04

### Fixed
- **The SDDM login theme actually applies now, and uninstalling it no longer
  breaks login.** The installer pin moves to imi-sddm-theme `36f5c93`, which
  carries three fixes. The scripts that copy your wallpaper and colours into the
  installed theme were still using the theme's pre-fork name, so since the
  rename *no* install had applied either — the greeter kept the stock background
  and stock colours, and the matugen hook failed on every wallpaper change,
  while the installer reported success. Uninstalling removed the theme directory
  but left `Current=` and the greeter's import path naming it, which is a login
  loop on the next boot: the password is accepted and the greeter returns. And
  the config drop-in sorted before KDE's `kde_settings.conf` and lost to it, so
  on any system where the KDE Login Screen module had been used the install
  silently changed nothing.
- **An M3 vertical bar is no longer completely unblurred.** Under that corner
  style the bar's two blur regions both resolve to nothing, so it declared an
  empty region while the whole-surface blur stayed switched off — the same
  defect already fixed for the horizontal bar. Its three material pills are now
  covered.

## [0.14.5] — 2026-08-04

### Fixed
- **Uninstalling no longer deletes your login shell.** `fish` is a dependency of
  the fonts-and-theming meta package, so removing Immaterial Impulse removed it
  too. For anyone who logs in *with* fish that was a lockout, and a confusing
  one: SDDM starts the session through the user's login shell, so the password
  was accepted and the greeter came straight back, exactly as if it had been
  rejected. The uninstaller now moves that shell to `/bin/bash` first — but only
  when the shell is one it is about to delete and only when it is the reason it
  goes, since a `fish` you installed yourself survives the uninstall untouched.
  Other accounts on the same shell are reported with the command to fix them
  rather than edited. Immaterial Impulse has never set anyone's login shell.
- **The OSDs, the search bar and the overview no longer frost their own drop
  shadow.** They were the last panels publishing no blur region, so the
  compositor blurred the whole layer surface — including the translucent shadow
  in the elevation margin — instead of just the painted body. They now follow
  the bar, the sidebars and the dock. The "Niri Like" overview style paints no
  body card, so its workspace rows trade backdrop blur for a crisp shadow
  elsewhere; layer rules are per-namespace and cannot be made style-conditional.
  A new lint pins the QML region and its Hyprland layer rule together, since
  either half alone renders wrong without erroring.

## [0.14.4] — 2026-08-04

### Fixed
- **A wallpaper that wedged on load could corrupt the next one.** The installer
  pin moves to `qs-wallpaperengine` v0.2.1. When a wallpaper hangs inside
  Wallpaper Engine's own `setup()`, its render thread never observes the stop
  flag, so the shell detaches it rather than freezing — but it then freed the
  object that thread is still running inside. A replacement of exactly that size
  is allocated moments later and lands on the same address as often as not, at
  which point the dead wallpaper publishes its texture and fence into the live
  one's state. Existing installs need one *Update Dots* run to pick it up.

## [0.14.3] — 2026-08-04

### Fixed
- **Install no longer aborts on the first package with "Cannot find the
  debugedit binary".** Nothing here builds debug packages, but that does not
  matter: makepkg checks for `debugedit` as a *precondition*, gated only on
  whether `debug` is set in `makepkg.conf`, so a missing `debugedit` killed the
  very first `makepkg` call — before anything compiled, and even for the meta
  packages that build nothing at all. `debugedit` is a `base-devel` member that
  was added after `base-devel` stopped being a pacman *group*, and group members
  are never pulled in retroactively, so long-lived Arch installs commonly lack
  it. We only ensured `base-devel` inside `install-yay()`, which is skipped
  whenever yay is already present — so the installs most likely to be missing a
  latecomer were exactly the ones that never got it. `base-devel` is now ensured
  unconditionally before the first build.

## [0.14.2] — 2026-08-03

### Fixed
- **A live wallpaper keeps animating while a fullscreen window sits on another
  workspace.** It used to stop dead on a still frame — visible, but frozen —
  from the moment anything anywhere went fullscreen until it left fullscreen
  again. None of that was the shell's doing: the embedded
  `linux-wallpaperengine` pauses *itself*. Its `pauseOnFullscreen` defaults on,
  its Wayland detector counts every fullscreen toplevel the compositor
  advertises — workspace and visibility are not part of the test — and
  `WallpaperApplication::render()` then early-returns, pausing mpv with it.
  Measured on a video wallpaper: the WE render thread kept looping at 0.7% CPU
  with 59 of 60 samples parked in `nanosleep` and its h264 decode threads at
  0.0%, against 3.0% and 71.7% when animating; frame-to-frame change over the
  desktop was exactly 0.0000 against ~7.2. `qs-wallpaperengine` 7e58913 passes
  `--fullscreen-pause-only-active`, narrowing that count to *activated*
  toplevels — a window holds activation exactly while it is focused, which is
  exactly while it covers the wallpaper. So a live wallpaper idles when it is
  behind a fullscreen window and animates whenever it is on screen, which is
  what the pause was always meant to mean. The installer pin now points there;
  existing installs need one *Update Dots* run to rebuild.
- **The wallpaper no longer strobes or goes black around fullscreen windows.**
  `hideWhenFullscreen` hid the wallpaper by setting `visible: false` on its
  window. Under `WlrLayershell` that does not hide anything — it destroys the
  `QQuickWindow` outright, since window reuse is forbidden there — so every
  fullscreen transition tore down the layer surface and brought it back on a new
  scene-graph GL context, forcing the embedded Wallpaper Engine renderer to
  rebuild against it. The visible results were a wallpaper that came back black
  after switching workspaces, and a desktop strobing at 30Hz: a screen recording
  of it alternates between the wallpaper and a transition shader sampling a
  texture that no longer exists, mean luminance swinging 61↔99 on every single
  frame at 60fps. The window now stays mapped and its *contents* are switched
  off instead, so there is nothing to destroy; the wallpaper resumes animating
  the moment the fullscreen window is gone. Twelve workspace flips past a
  fullscreen window used to mean twelve surface teardowns and twelve renderer
  rebuilds — now zero of each. The switch transition also has a watchdog, so a
  wallpaper change that stalls settles instead of hanging half-peeled.
- **Fullscreen and maximized are told apart.** The wallpaper and the screen
  corners now test true fullscreen only, read from a per-monitor map polled from
  `hyprctl`. Neither Hyprland's own `hasfullscreen` flag nor a toplevel's
  `wayland.fullscreen` makes that distinction.
- **The M3 bar is blurred again.** Nothing on it was — not the gaps, not the
  pills. `Bar.qml` scopes the compositor blur through a `WindowBlurRegion`, and
  that region listed only the full-width background strip and the non-M3 centre
  pill, both of which resolve to null under M3. So the region was empty and the
  Hyprland layer rule had nothing to act on, which is what made it look like a
  compositor problem. M3's three painted wrappers are now handed to the region,
  so blur covers exactly the shapes that are painted and the gaps stay clear.
- **The bar styles agree on their margins.** Each style open-coded its own, so
  they drifted: Hug carried a top margin despite sitting against the monitor
  edge, and Islands subtracted 6px from its exclusive zone, reserving less than
  it drew. They now derive from one pair of tokens — Hug has no top margin, the
  three detached styles share one, and all four share the bottom margin (the gap
  to the windows below, or beside, when the bar is vertical).
- **Islands pills have room for their contents.** Islands is the only style
  where each group *is* the visible shape, with fully-round ends, so the shared
  4px of padding was mostly eaten by the curve and content sat on the edge —
  most visible on the weather widget, whose text is essentially the whole pill.

## [0.14.1] — 2026-08-03

### Fixed
- **Notifications relayed from a phone show their formatting again.** They
  arrived rendering literal `<b>` and `<br/>`. The renderer was never at fault
  — the popup parses markup and we advertise `body-markup` on the bus. Captured
  the `Notify` call to be sure: KDE Connect relays the phone notification's
  text verbatim and runs one `toHtmlEscaped()` over it, and apps like Teams on
  Android put HTML in that text, so the markup arrived escaped. The quotes
  proved it was exactly one level (`&amp;quot;` is escaped twice, which only
  happens over input that was already HTML), so one decode inverts it. Scoped
  to that sender: every other app escapes the non-markup parts of its body
  exactly as the spec asks, and decoding those would corrupt them.

## [0.14.0] — 2026-08-03

### Changed
- **The SDDM login theme is now named `imi-sddm-theme`**, in the installer menu
  and on disk. Existing installs migrate on the next update: the theme's
  installer repoints every `[Theme] Current=` naming the old theme before
  removing anything, because SDDM resolves that value against
  `/usr/share/sddm/themes` and reads `/etc/sddm.conf.d/*.conf` in lexical order
  — so the file that decides is frequently `kde_settings.conf`, written by the
  KDE settings module rather than by us, and dropping the old directory while
  that still named it would leave no greeter at all. The old directory, drop-in
  and scripts are removed only once the replacement is fully in place, so an
  interrupted migration leaves the old install working rather than half-gone.
  Our side accepts either name throughout the transition, including the matugen
  `post_hook` restore, which prefers the new one — both directories exist at
  once mid-migration.

### Fixed
- **The Android quick toggles stop scrambling when you edit them.**
  `DelegateChooser` picks a component when a delegate is *created* and never
  re-picks for one that survives a model update, so a row entry that changed in
  place kept the previous toggle's component — its icon, name and action —
  while carrying the new entry's data. Rows are packed by toggle size, so
  nearly every edit reflows them and moves entries across row boundaries, which
  is exactly that in-place change. The rows now use a plain array model, which
  resets the delegates so each is chosen for the type it actually holds. The
  stored layout was correct throughout, which is why restarting the shell
  appeared to fix it. Covered by a runtime test that renders the real panel and
  performs each edit — the earlier attempt kept only same-row reorders honest,
  which is why it looked fixed and was not.
- **The login screen shows the current wallpaper again (second attempt).** The
  SDDM fork was retargeted for the installer only, and its `setup.sh` clones
  the theme content from its own `THEME_REPO` rather than copying the checkout
  it runs from — that still pointed at upstream, so every install laid
  upstream's theme back down over the fork's. The installed theme therefore
  still read `~/.config/illogical-impulse/config.json`, a directory the 0.13.1
  purge removed, and had no Wallpaper Engine handling at all, so the greeter
  fell back to a stock background. The fork now installs itself, and the
  installer pin is a full commit SHA checked by a test.
  Wallpaper Engine is also resolved *before* the static wallpaper now, rather
  than only when `background.wallpaperPath` is empty: selecting a WE wallpaper
  does not clear that key, so any install that used a static wallpaper first
  kept showing the old picture on the login screen. The order now matches
  `Background.qml`'s `weActive` — a WE project wins unless it is a "web" one,
  which the shell cannot render either.
- **Switching keyboard layout works again (#69, second attempt).** The previous
  fix cleared the stale `input.kbOptions = grp:win_space_toggle` from
  `config.json` and changed nothing on any real machine, for two independent
  reasons. It was guarded by a persisted "already migrated" marker, and a
  marker records that the check ran, not that the value was ever there — an
  install whose config-directory migration declined burned it against the
  installer's default and then received the user's real config afterwards,
  permanently out of reach. And `config.json` is not what Hyprland reads: the
  option reaches the compositor through the generated
  `hypr/hyprland/shellOverrides/main.lua`, which is only rewritten when the
  Hyprland settings page is opened, so the clear never arrived there. The clear
  is now unconditional — `grp:win_space_toggle` is not a value the shell can
  hold legitimately, since the settings control offers only "none" and
  Alt+Shift — and it purges the generated lua too, through a new `--reset-if`
  mode that removes the managed line only while it still holds the stale value.
  Both halves are covered by a runtime test against real files; the old fix had
  no test at all, which is why it shipped broken. Symptoms: Super+Space fired
  the xkb toggle *and* the compositor bind, two switches that cancelled, so the
  OSD announced a layout change that had not happened, while Super+Alt+Space
  switched the layout on top of toggling the window float.

## [0.13.1] — 2026-08-03

### Fixed
- **The login theme follows the desktop again, and installs unattended.** The
  SDDM theme now comes from our fork (`XephyLon/imi-sddm-theme`). Upstream
  resolved the shell's config at `~/.config/illogical-impulse/config.json`, a
  path that stopped existing when the shell was renamed, so its "sync ii
  settings" mode had been syncing a copy frozen at the rename. It also had no
  non-interactive mode, so an unattended install EOF'd on its first prompt and
  exited having installed nothing; and it ignored Wallpaper Engine entirely, so
  the greeter fell back to a stock background exactly when the desktop was at
  its least default — it now plays a WE video wallpaper directly, or uses the
  still the shell renders for scene/web ones.
- **Wallpaper changes reach the login screen again.** The theme registers its
  trigger as a `post_hook` inside `~/.config/matugen/config.toml`, and the
  installer deploys that file with `rsync --delete` from a copy that has no
  such line — so every update deleted the hook and the greeter quietly froze.
  The installer restores it after deploying, deriving the right variant from
  what the theme actually installed.

- **The pre-rename config directory is archived and removed instead of being
  left behind.** Migrating `~/.config/illogical-impulse` into
  `~/.config/immaterial-impulse` used to keep the old directory in place as a
  backup. That is not harmless: anything resolving a config by absolute path
  finds the stale one and silently succeeds against it — `ii-sddm-theme`'s
  installer reads `~/.config/illogical-impulse/config.json` directly, so the
  login theme was syncing settings frozen at migration time and never saw
  another change. The directory is now archived to
  `~/.local/share/immaterial-impulse/backups/illogical-impulse-<timestamp>.tar.gz`
  and removed, and installs that already migrated under the old behaviour get
  their leftover cleaned up on the next launch. The archive has to write and
  read back before anything is deleted, so a full disk keeps the directory
  rather than losing it.


## [0.13.0] — 2026-08-03

### Added
- **Settings now survive the move from upstream.** Arriving from
  `end-4/dots-hyprland` or `pctrade/end4-pC` already moved your config
  *directory*; it never converted anything inside it. The shell reads
  `config.json` through a JSON adapter that silently ignores any key it does not
  recognise, so a setting this fork renamed was replaced by a default with no
  error and nothing to point at. Two things were being lost and are now carried
  across on first launch:
  - **`panelFamily`.** A config naming `ii` or `waffle` (end-4's second panel
    family, which was never ported here) matched no panel family at all - the
    desktop came up **completely blank**: no bar, no dock, and no error in the
    log. Both now resolve to `imi`.
  - **`bar.floatStyleShadow` -> `bar.shadow`.** Not a straight copy. Upstream
    only ever drew that shadow under the Float corner style, while ours draws it
    under every style that paints a background, so what migrates is the shadow
    you actually had on screen rather than the flag on disk.

  Everything else in the schema turned out to be intact - this fork's key set is
  a superset of upstream's, with no type changes and nothing moved to a different
  parent. The keys that were *removed* rather than renamed (`waffles.*`, and
  end-4's `notifications.monitor.*`, which nothing ever read) are recorded as
  removals rather than given an invented destination. The full audited
  old-key -> new-key table, and an explicit list of what is **not** covered
  (`~/.config/hypr/`, `~/.config/matugen/`), is in `docs/UPSTREAM_MIGRATION.md`.

  It runs once, keyed on a marker of its own rather than on the old directory
  still existing - that directory is already gone for anyone whose directory
  migration ran earlier, and those are exactly the people who still need this.

### Changed
- **Notes are a list of notes again, not one scratchpad — and both notes
  surfaces now share it.** The notes desktop widget and the overlay notes
  editor (`Super`-summoned overlay) used to share a single plaintext file, so
  there was only ever one note. They now share a JSON array of separate notes,
  stored in the same file as before
  (`~/.local/state/quickshell/user/notes.txt`). **What happens to your existing
  text:**
  - Whatever is in your scratchpad today becomes your first note, word for
    word. Nothing is deleted, and a file that cannot be parsed is kept as a
    note rather than reset.
  - If you used the old built-in notes widget (removed earlier in this cycle),
    the notes it kept in `~/.local/state/quickshell/user/desktopnotes.txt` are
    **imported back** and will reappear alongside your scratchpad. That import
    runs exactly once; notes you delete afterwards stay deleted.
  - `desktopnotes.txt` is read and then left alone forever — it is never
    modified or removed, so it remains your own copy of those notes.
  - `notes.txt` now contains JSON rather than raw text. If you edit or sync it
    by hand, expect an array of `{ id, content, attachments, createdAt }`.
    Replacing it with plain text is safe: it is read back as a single note.
  The desktop widget gets a list of notes, an add button, a per-note delete
  button and a flip to a full-size editor. Swipe-to-delete and the old
  per-note colour cycling from the removed built-in were **not** restored. The
  overlay editor keeps its editor and its copyable-bullet buttons, and gains a
  strip of note chips plus add and delete buttons, so it can reach every note
  instead of only the first. Adding, editing or deleting a note in one surface
  shows up in the other immediately.
- A fresh install now ships the clock and the visualizer on its desktop, not
  the calendar. Both of the two sit at an edge - the clock centred, the
  visualizer full-bleed along the bottom - so neither claims a tile the user
  has not chosen to give it. Existing installs are untouched: the curated
  defaults are seeded only when `~/.config/immaterial-impulse/config.json` does
  not already exist.

### Fixed
- **The night light indicator now tells the truth, and your setting survives a
  restart.** The toggle and the bar indicator could say night light was on with
  a perfectly neutral screen, or off with a warm one. The shell was asking
  `hyprsunset` what it was doing, and `hyprsunset` cannot answer: its only
  requests are `temperature`, `identity` and `gamma`, and the `temperature`
  query reports the last temperature the daemon was *told* — turning night light
  off with `identity` never changes that number. The shell then compared it
  against a hardcoded `6500`, which was never `hyprsunset`'s neutral to begin
  with (it is the cool end of the Intensity slider; the daemon's own default is
  6000 and its neutral is the identity matrix, not a temperature). The answer
  was therefore wrong on essentially every restart. The shell now remembers
  whether you had night light on and re-applies it on startup instead of
  guessing — so the setting survives a reboot, and turning it off actually stays
  off. Automatic scheduling is unchanged: startup restores what you last had and
  never consults the clock, so it still does not switch itself on just because
  you logged in after sunset.
- **Opening a Settings page no longer eats the setting you had.** Every numeric
  setting is edited through a spin box or slider that declares its own range —
  the OSD timeout's box, for instance, stops at 3000 ms. Nothing in the config
  format does: `osd.timeout` is a plain number and the shell honours whatever is
  in it. Those controls used to report the value being *loaded* as if it were a
  value you had just typed, so a config holding `4321` was quietly cut down to
  `3000` and written back to disk **the moment the page was drawn** — no prompt,
  no warning, and nothing you did. Anything you set by hand, restored from a
  backup, or imported from a preset outside a control's range was lost on the
  first look at the page that shows it, and the same round trip rounded off
  fractional values (a 90-second wallpaper interval became 60, a 0.185 overview
  scale became 0.18). Sliders were worse: their smoothing animation wrote every
  intermediate frame of it.

  Controls now write only when you actually move them, and a stored value
  outside a control's range is shown as it is rather than silently pinned to the
  nearest end — so you can see the real number and, if you want, walk it back
  into range. Values already inside a control's range behave exactly as before.
- **The "−" button on every number field was almost unclickable.** Only its
  leftmost few pixels did anything; the rest of it sat underneath the editable
  number, which swallowed the clicks. The whole button works now. Number fields
  are a little wider as a result.
- **Click through only made half of a widget click-through.** A desktop widget
  switched to **Click through** stopped taking the drag and stopped swallowing
  the desktop's right-click menu — but every control the widget drew for itself
  kept working, and a click that landed on one never reached the desktop behind
  it. The widget host is a `MouseArea`, and disabling a `MouseArea` disables
  only that one area, not the items inside it; the mechanism read as if it
  disabled the whole widget and never did. Everything a desktop widget draws now
  sits inside a wrapper that goes inert with it, so **Click through** means what
  the switch says: the widget is transparent to the pointer, controls included.
  Nothing visibly changes and no widget changes size. Only the Visualizer ships
  click-through on, and it has nothing to click, so nobody was hitting this yet —
  it is fixed before anything else opts in. Pinning a widget with **Lock
  position** still leaves its controls working, which is the difference between
  the two switches.
- **Coming from upstream no longer silently loses your entire settings
  directory.** Moving `~/.config/illogical-impulse` to
  `~/.config/immaterial-impulse` is done at first launch by a script that
  refused to migrate into a directory that already contained a `config.json`.
  That guard cannot tell your config from a file you have never seen, and two
  things routinely put one there before it ran:
  - **The installer put it there itself.** It seeds the curated
    `defaults/config.json` into `~/.config/immaterial-impulse` whenever it finds
    no config there — which is always true for someone arriving from upstream,
    because theirs is still under the old name. The migration then found that
    seeded file in the way and skipped the whole directory. No race needed; this
    happened to everyone who used the installer.
  - **The shell could get there first.** The migration was launched and then not
    waited for, so it ran alongside the shell's own config load. When the shell
    won, it wrote a default `config.json` into the destination and the migration
    skipped the directory for the same reason.

  Either way you kept none of your settings, none of your custom actions,
  presets or AI prompts, and there was nothing in the log to say why. Your old
  directory was never deleted, so nothing was ever destroyed — but you had no
  way to know that was where your settings still were.

  Now: the shell waits for the migration to finish before it reads or writes the
  config directory at all, and the migration decides by comparing the file in
  the way against the config this shell ships. An untouched shipped default is
  replaced by your real config; anything you have actually changed here is
  **never overwritten** — instead the shell declines, changes nothing, and logs
  which directory your settings are still in so you can merge them by hand. If
  the migration itself gets stuck, the shell still comes up, but read-only, so a
  half-finished move can't cost you the file. A successful merge keeps the old
  directory as a backup; delete or rename it once you no longer want it.
- The design-system compile check swept a hardcoded list of bundled packages
  that had rotted: it still named `nandoroid-clock` and `nandoroid-at-a-glance`,
  directories that have never existed at that path, so every run reported two
  meaningless failures. Both roots are discovered with `find` now, so the check
  covers every bundled package's entry point (118 files, up from a fixed list)
  and cannot drift again; a sweep that matches nothing fails instead of passing
  silently. It is also wired into `tests/run_tests.sh` for the first time -
  nothing ran it before, which is why the dead names survived since the ii->imi
  rename. It skips where there is no Wayland display, so CI is unaffected.

### Added
- **Per-widget lock and click-through for desktop widgets.** Every desktop
  widget gains two switches of its own next to `Blur background` in
  Settings → Widgets. **Lock position** pins that one widget while the rest
  stay draggable; it combines with the existing global `Lock widget positions`
  rather than replacing it, so the global switch can only ever lock further and
  never unpins something you pinned deliberately. **Click through** takes the
  widget out of pointer input entirely, so clicks land on whatever is behind it
  — including the desktop's own right-click menu. They stay two separate
  switches because "pinned but still clickable" is a real thing to want; the
  reverse is not, so click-through implies the lock. A plugin can ship either
  one on by default from its manifest (`desktopWidget.locked`,
  `desktopWidget.clickThrough`), and you can still switch it back off.
- **The Visualizer now ships click-through on.** It spans the full width of a
  monitor and has nothing on it to click, so it was covering a whole strip of
  desktop, swallowing the right-click menu there, and could be dragged half
  off-screen with no bounds. Switch its click-through off if you want to
  reposition it.
- **`shape` and `color` manifest option types.** `shape` takes the same
  `choices` array as `choice` but renders each entry as the Material shape it
  names rather than as a text chip — a 31-entry row of shape *names* is
  unreadable, and `ConfigSelectionArray`'s chip flow only wraps when the row
  has no label, so such a row could not be labelled either. `color` renders a
  row of palette swatches from `Appearance.colors` role names; the empty
  string is a legal choice and draws an "automatic" slot, so a widget with a
  sensible colour of its own gets its override *and* the way back to that
  default in one row, rather than a second switch sitting beside the row
  saying the same thing.
- **A `grid`-exempt escape hatch for full-bleed widgets.** The component grid
  caps at 12 columns (1716px — barely a third of a 5120px display), so a
  screen-wide widget cannot express itself through `grid` at all. It omits
  `grid`, takes the host's content sizing, and binds its own `implicitWidth` to
  the monitor the host tells it it is on. `docs/widget-grid.md` documents the
  rule and the two other legitimate exemptions (user-resizable, and square).
- **Host opt-ins for widgets that draw straight onto the wallpaper.** A package
  component may now declare `visibleWhenLocked` (stay up while the screen is
  locked, regardless of `lock.showWidgets`), `forceCenter` (centre on the
  monitor without disturbing the persisted position), and `needsColText` (run
  the least-busy-region pass so `hostColText` tracks the wallpaper underneath).
  The bundled Clock uses all three. Every one is optional; a widget that
  declares none behaves exactly as it did before.

### Changed
- **The two desktop-widget systems are now one.** Every desktop widget used to
  be either a hardcoded `FadeLoader` in `modules/imi/background/Background.qml`
  gated on `background.widgets.<key>.enable`, or a bundled plugin gated on
  `plugins.enabled`. All eleven built-ins are gone: seven were ported to
  bundled plugins (Visualizer, Custom Image, Image Converter, User Card, World
  Clock, Calendar, Clock) and four were deleted as duplicates of a plugin that
  already shipped (resources → System Monitor, media → Media Player, weather →
  Weather, notes → Notes). Every desktop widget now goes through one code path
  (`PluginManager` → `PluginWidget` → `PluginNode`) and is enabled from
  Settings → Widgets — which means one frost/blur implementation, one position
  persistence system, and one place to look. Porting the clock also retired the
  older declarative `clock_plugin`, so there is exactly one clock in the list.
- **Nothing you had switched on switches off.** A one-shot migration translates
  `background.widgets.*.enable` into `plugins.enabled`. The clock gets a second
  one: it is the only widget that shipped *on*, and its four styles look
  nothing like one another, so it carries its own settings and its desktop
  position across as well rather than silently repainting and moving itself.
  Both migrations are marked so they never run twice, and the clock's marker is
  written only once the values have actually landed.
- **The world clock's timezones moved in with the rest of its settings.** They
  were the last thing in the old desktop-widget config block that the shell
  still wrote to while running; they now live in `plugin-state.json` alongside
  the widget's other options. A third one-shot migration carries an existing
  list across — including on installs that had already run the two earlier
  ones, which is all of them — and a list you have since changed through the
  widget's own picker always wins over the one being migrated. The four zones
  you picked survive the upgrade; there is nothing to redo.

### Fixed
- **A locked widget could still be resized.** The Calendar, World Clock and
  Custom Image each draw a corner grip that resizes them, and each one checked
  only the global `Lock widget positions` switch. Lock one of those widgets on
  its own and the lock held for dragging but not for the grip — the widget was
  pinned and still fully resizable, which is not what "locked" means anywhere
  else. All three grips now follow the same resolved lock the drag does, so a
  widget locked for any reason (its own switch, the global one, or
  click-through) has a dead grip. That also closes a hole in **Click through**:
  the widget itself stopped taking clicks, but a grip drawn *inside* it did
  not, so a click-through widget could still be resized by its own handle.
- **Laptops lost their battery reading when the resources widget was deduped.**
  The built-in `ResourcesWidget` showed CPU, RAM and — wherever a battery
  existed — the battery, falling back to disk only on a desktop. The bundled
  `nandoroid-system-monitor` it was deduped into is always Disk, so every
  laptop the migration moved onto the plugin quietly lost the reading. The
  third card follows the battery again, gated on `Battery.available` rather
  than the raw display device, so a transient UPower device swap cannot make
  the whole card flip to Disk and back. The plugin also gains a **Battery
  instead of disk** switch (on by default): the built-in never let a laptop
  user keep disk, and that guess is wrong for anyone who put the widget there
  to watch it. A machine with no battery renders exactly what it did before,
  to the pixel.
- **The world clock card overflowed its own bottom margin, and always had.**
  Its content came to 6px more than the card at both the old height and the
  new one, so the bottom row of city chips sat 2px off the card edge while the
  top sat on a full margin. The chips now take the column's leftover height
  instead of a fixed 50px, so the card cannot be overshot by a font that
  renders a little tall, and they divide the card width instead of being a
  fixed 120px block centred inside it — they line up with the header and the
  time above them now, down both edges. The local time drops 42px to 36px,
  which is where the room for a real `space150` card inset comes from; it is
  still 2.4× the largest text under it. The timezone-picker side gets that
  same inset and a heading, instead of a back arrow alone against an empty row.
- **The wide world clock drew each city's name through its own clock hands.**
  `AndroidClock` placed the label just under the centre dot while the minute
  hand reaches 0.82 of the dial radius, so the two always overlapped. A
  labelled clock now reserves a band for the label and centres the dial in
  what is left; an unlabelled one (the clock preview in Settings) is laid out
  exactly as before. The label also picks up the shell's own font instead of
  asking the canvas for `sans-serif`.
- **The calendar's padding was whatever made it fit.** Putting the widget on
  the real grid cell left every gap inside it set to whatever absorbed the 24px
  it lost, so the month title, the weekday letters and the day grid all sat the
  same 4px apart with nothing saying which belonged to which. All three sizes
  now share one card inset and one three-step rhythm — `space150` around the
  card, `space100` between the title block and the calendar block, `space50`
  between the weekday letters and the grid they label. The day columns spread
  across the full card width instead of sitting as a fixed 196px block centred
  in a 252px surface, so the weekday letters line up over the days they name
  and the day block is inset evenly on all four sides; the week strip is
  centred in its card rather than piled against the top with all the slack
  under it.
- **Every "2×2" world clock and calendar was 24px too tall.** Both assumed a
  132×**120** grid cell; the cell is 132×**108**. A widget off the lattice
  cannot line up with its neighbours no matter where it is dropped — its bottom
  edge lands past every other tile's, on every row. Both are now sized through
  `Appearance.sizes.widgetGridSpanX/Y`, which also makes them follow
  `effectiveScale` instead of being wrong on every scaled setup.
- **Every unselected shape in a shape picker rendered invisible.**
  `ConfigSelectionShapeArray`'s default `shapeColor` was `colPrimaryContainer`,
  near-identical to the chip background it was drawn on.
- **The desktop media widget would have thrown on its first reset.**
  `Background.qml`'s media `onLoaded` referenced a `mediaTimer` that was
  declared nowhere in the tree.
- **The cookie clock's Gemini auto-styling would have silently stopped.**
  `scripts/colors/switchwall.sh` read `.background.widgets.clock.cookie.aiStyling`
  out of `config.json`. The clock's settings live in `plugin-state.json` now, so
  that read would have returned `"null"` forever and the wallpaper category
  would never have been generated.
## [0.12.0] — 2026-08-02

### Added
- (#75) Kitty terminal colors now follow the wallpaper through a matugen
  template, so its palette re-themes together with the shell and other apps on
  a wallpaper change (alongside the existing terminal palette pass).

### Fixed
- Super+Alt+Space (window float toggle) no longer also switches the keyboard
  layout. The shipped default config still carried `input.kbOptions =
  grp:win_space_toggle` even after the layout switch was moved to a compositor
  bind — xkb `grp:` toggles match modifiers loosely, so Super+Space fired with
  Alt held too. Fresh installs now seed `kbOptions = ""`, and a one-time
  migration clears a stale `grp:win_space_toggle` from existing configs on the
  next shell start, so both are fixed. Super+Space then runs only the
  exact-matching `switchxkblayout all next` bind, which cycles the real
  `us, eg` layout list and reverses cleanly.
- (#70) The wallpaper no longer disappears after a transition on OpenGL
  2.1-class GPUs. The Doom melt transition used a `const int[256]` table and a
  bitwise `&`, which the GLSL ES 1.00 profile the RHI compiles to on those
  backends rejects, so its shader failed to build and left the desktop blank.
  The shader now compiles there (procedural noise, `mod` instead of `&`), and a
  transition-shader compile error falls back to the plain wallpaper instead of
  blank output.
- (#71) A bar hover popup opened next to a closing one (e.g. weather after
  clock) is no longer painted over by the one still finishing its close
  animation. Adjacent popups are separate layer-shell surfaces, so stacking
  order — not activeness — decided which drew on top; a lingering popup now
  collapses the moment a neighbour opens.
- (#72) The SDDM login theme (ii-sddm-theme) no longer silently fails to
  install from the default TUI. Its upstream installer is interactive, but the
  default fzf TUI ran the install pipeline with stdin from `/dev/null`, so the
  installer hit EOF on its first prompt and aborted with no output. It now runs
  as an interactive post-install step on the real terminal, and the wrapper
  reconnects to `/dev/tty` (or skips with a message) instead of aborting.

## [0.11.0] — 2026-08-02

### Changed
- The **Plugins** settings page is now **Widgets**, with a search field and
  capability filter chips (Desktop, Bar, Overlay, Panel). Type names, file
  names and the `plugins.*` config keys are unchanged, so existing installs
  are unaffected.
- `FilterChip` moved from a page-local component inside the gated-off plugin
  store to `modules/common/widgets/`, so both filter surfaces share one
  implementation. The capability vocabulary moved to
  `PluginManager.surfaceCapabilities` for the same reason.
- Widget cards are restacked: the name shares its line with a byline, the
  description gets the second, and **surface tags** run along the third, drawn
  from the same vocabulary as the filter chips so a card explains why a filter
  matched it. The byline is trimmed to creator and version — manifest authors
  routinely append the repo or a contributors note. Row actions sit before the
  switch, and the third-party badge is error-coloured: not because such a
  widget is broken, but because it runs with the shell's own access and came
  from outside it.
- `ConfigSwitch` gains `titleContent`, `detailContent` and `trailingContent`
  slots. Its label is one text item and its switch is the last thing it draws,
  so a caller previously could not put anything beside either. The third-party
  pill and the surface tags share a new `Badge` widget rather than
  open-coding the same pill twice.
- Widget settings (frost, blurred opacity, install-from-URL) moved into their
  own section. They describe how widgets behave, not which ones the list is
  showing, and they had been standing between the "Available Widgets" header
  and the list it names.

### Fixed
- **A band of dead space sat under every enabled widget.** An expanded panel
  computed its height as content plus a 20px inset unconditionally, so one
  that opened onto nothing still claimed the inset — visible under widgets
  exposing no options, and under every enabled widget until its options
  finished loading.
- Row actions were pushed past the card's right edge. A wrapping description
  reports its full unwrapped width as its implicit width, and the row honoured
  that as a minimum, so the card could not shrink to fit its own buttons.
- **A widget's options disappeared when a filter was selected.**
  `ExpandablePanel` only ever received a height from `animateTo()`, which runs
  solely from `onExpandedChanged` — so a panel *created* already expanded never
  emitted the signal, never got a height, and rendered its content clipped to
  nothing. Selecting a filter rebuilds the list's delegates, so every enabled
  widget came back open-but-empty until its switch was toggled off and on.
  Affects any call site that creates a panel in the expanded state.
- Plugins declaring `overlay-widget` (Discord Voice) were missing from the
  capability vocabulary entirely and matched no filter.
- Widgets whose manifest predates the `capabilities` key (the bundled clock)
  matched no filter chip and vanished from every filtered view.
- Settings labels rendered through `ConfigSwitch`, and icon names rendered
  through `MaterialSymbol`, inherited Qt's `Text.AutoText`, so an installed
  plugin manifest could inject rich text into the settings UI through its
  name, description or option icons. Both now render as plain text.
- An empty widget list claimed the filters were responsible even when none
  was set — reachable on first paint, since the manifest scan is async.
- Searching settings for "widgets" could not reach the Widgets page: the name
  collided with a section of Wallpaper & Desktop, which is matched first. An
  exact page-name match now wins over any section match.

## [0.10.0] — 2026-08-01

### Added
- `ExpandablePanel` gains a **clickable header**: the whole row becomes a
  ripple surface, so a panel whose header holds only a small chevron no
  longer feels dead next to one filled by a switch. It reports the click
  rather than toggling itself, so a call site that binds `expanded` to its
  own state keeps that binding.
- `RippleButton` gains **per-corner radii** and an **`appear`** reveal
  factor, so the fourteen shared buttons derived from it can sit in a
  panel header or cascade in without either capability being re-derived at
  each call site.
- A developer gallery for judging the panel's optional traits side by side
  against the defaults (`qs -p ExpandablePanelGallery.qml`, not shipped).

### Changed
- The settings page's plugin cards are now built on `ExpandablePanel` too,
  so they and the Docker popup's container cards share one implementation
  rather than resembling each other. Both toggle from anywhere on the
  header, with a ripple across the row.
- Staggered content rises into place as it appears, and animates out
  instead of snapping.

### Fixed
- Expanding a panel jolted instead of gliding. The vertical insets were
  applied in a single frame while only the content height eased, so the
  card jumped ~21px and then animated the rest.
- Every expansion after the first ran the *collapse* curve — accelerating
  instead of decelerating — because one animation chose its duration and
  easing from a ternary that had not re-evaluated by the time it started.
- Collapsed content was excluded from layout while hidden, so re-opening
  animated toward a stale height and corrected mid-flight.
- Disabled buttons inside an expanded panel rendered as if enabled. The
  staggered reveal wrote `opacity` directly, destroying the binding that
  expresses the disabled state.
- A panel header's hover and ripple kept rounded bottom corners while
  open, leaving notches against the content below.

## [0.9.2] — 2026-08-01

### Fixed
- **"Update Dots" now updates the components you actually have.** Every
  optional component defaulted to unchecked in the installer's checklist,
  and that installer is also the updater — so someone who installed
  Wallpaper Engine and later clicked Update Dots got the menu with it
  unticked, the step exited immediately, and the component was never
  updated. Wallpaper Engine, the SDDM theme and the Plymouth splash are
  now pre-selected when they are already installed.

  This is what kept the 0.9.0 and 0.9.1 crash fixes from reaching anyone
  who updated through the button rather than a terminal. An unchecked box
  in an updater is a silent skip, not a neutral default.

## [0.9.1] — 2026-08-01

### Fixed
- **Re-running the installer now actually repairs the Wallpaper Engine
  wrapper.** 0.9.0 fixed the library-path leak that crashed apps launched
  from the shell, but no existing install could receive the fix: the
  installer skips its work when the build stamp matches and the wrapper
  file exists, and it exited before rewriting the wrapper. Updating,
  re-running the installer and restarting all looked like no-ops while the
  old wrapper stayed on disk. The stamp guards the expensive fetch and
  build, never the wrapper, which is now always rewritten.

  If you followed 0.9.0's "re-run the installer" note and Firefox kept
  crashing, this is why. Re-run it once more on this version.

## [0.9.0] — 2026-08-01

> **Wallpaper Engine users: re-run the installer.** This release fixes a bug
> where apps launched from the shell inherited the wrapper's library path and
> could crash on startup. The fix lives in the wrapper at
> `/usr/local/bin/quickshell`, so it only takes effect once the Wallpaper
> Engine install step runs again.

### Added
- **`ExpandablePanel`** — a shared, plugin-facing component for rows that
  expand, implementing every Expandable Content rule in the M3 guidelines:
  asymmetric enter/exit motion, opacity paired with the height, clipping,
  content that stays alive until its exit reaches zero, a leading-edge
  indent, and collapsed content that takes no keyboard focus. The outline,
  hairline rule, shape morph, tonal lift and staggered reveal are all
  optional properties, so plugin authors get correct behaviour by default
  and can dress it to match their widget.

### Changed
- Docker container and Compose cards are built on `ExpandablePanel`. They
  gain the correct collapse curve, a paired fade, input gating and a
  staggered reveal of their action buttons.
- **A fresh install now enables no plugins.** Seven were on by default,
  several of which paint on the desktop immediately, and their off switch
  lives under Plugins rather than Widgets — so people were finding widgets
  they could not work out how to remove. Existing installs are untouched.

### Fixed
- **Apps launched from the shell could crash on startup** on Wallpaper
  Engine installs. The wrapper exported `LD_LIBRARY_PATH` with the
  linux-wallpaperengine lib directories on it; that is inherited by every
  process the shell spawns, and those directories ship CEF's own
  `libEGL.so` and `libGLESv2.so`. Firefox resolved those instead of the
  system libraries and died during GPU init. The export was never needed —
  the binary already carries a `RUNPATH` — and is gone.

## [0.8.0] — 2026-08-01

Mostly a correctness release. Two of the fixes below were reported by
users and neither was ours originally — the quick-toggle scrambling came
in with the upstream absorb, and the Qt 6.8 requirement was a property
assignment nobody noticed was version-gated.

### Changed
- The **Docker plugin popup** is built from the shell's own M3 Expressive
  components instead of widgets it defined for itself: `SecondaryTabBar`
  over a `SwipeView` for the Containers/Compose switch, `StyledRectangle`
  cards, `FlowButtonGroup` + `RippleButtonWithIcon` action rows,
  `StyledFlickable` scrolling, `IconToolbarButton` header actions,
  `MaterialLoadingIndicator` for refresh, and `PagePlaceholder` empty
  states. Card expansion animates through a `Revealer` rather than
  toggling visibility, so neighbouring cards no longer jump.

### Fixed
- **Android quick toggles no longer scramble.** Editing the layout left
  every tile after the edit point showing the previous tile's icon and
  firing its action, while the delete and resize badges acted on the tile
  you could see — so you toggled one thing and deleted another. Changing
  the column count or importing a preset triggered it too, and it
  persisted after closing the sidebar. The Classic panel was unaffected.
- The Quick settings page no longer disappears on Qt older than 6.8.
  `StyledImage` assigned a 6.8-only property declaratively, which made it
  fail to compile and took down every page that used it — which among the
  settings pages was Quick alone.
- A settings page whose QML fails to build now says so instead of showing
  an empty pane beside a fully populated navigation rail.
- An unreadable `config.json` — wrong permissions, a bad mount — no longer
  leaves every settings page permanently blank. Only a missing file was
  handled before; any other read error left the config never marked ready.
- Quick page: the "Group style" and "Screen round corner" cards each read
  their height from the *other* card's column. Both sit in the same grid
  row, whose height is the larger of the two, so nothing rendered wrongly
  — but the bindings said something untrue about which card owns which
  height.
- Quick page: the scheme-preview command lost its virtualenv fallback to
  QML's template substitution (`${...}` is QML syntax too), which broke
  the whole binding and left the palette swatches without a command.
- The Docker popup is the 480px wide it always declared. The width sat on
  a `ColumnLayout`, which overwrites its own `implicitWidth` from its
  children, so the popup had been silently content-sized.

## [0.7.0] — 2026-08-01

Immaterial Impulse is an independent project now, not a fork that tracks
its ancestors. Nothing is pulled from `pctrade/end4-pC` or
`end-4/dots-hyprland` any more, and the code and naming that existed to
keep those merges tractable is gone.

### Changed
- **The shell is `imi`, not `ii`.** It installs to
  `~/.config/quickshell/imi` and runs as `qs -c imi`; the QML module
  namespace is `qs.modules.imi.*` and the panel family identifier is
  `"imi"`. `ii` was illogical-impulse's abbreviation. Existing installs
  are handled: a `panelFamily` of `"ii"` in an already-written config
  still resolves (without that, the shell would start with no panels at
  all), and the installer clears a leftover `~/.config/quickshell/ii`
  once the new directory is in place.
- The Python virtualenv variable is `IMMATERIAL_IMPULSE_VIRTUAL_ENV`.
  Every consumer falls back to `ILLOGICAL_IMPULSE_VIRTUAL_ENV` and
  `env.lua` exports both, so a Hyprland session started before the update
  keeps generating colors and thumbnails until the next login.
- The welcome screen's Usage, Configuration and GitHub buttons open this
  project's own docs instead of end-4's wiki, which describes a shell
  this one has diverged from. The sponsor button now says whose page it
  opens, and the repository's GitHub Sponsor button no longer routes to
  end-4.
- README and AGENT.md describe the fork relationship in the past tense.
  Attribution to end-4 and pctrade stays in `LICENSE`, `licenses/` and
  the credits — the project is GPL-3.0 and the ancestry is real.

### Removed
- The compositor abstraction. `WM` absorbed `HyprlandBackend` (its API is
  unchanged, so no call site moved), `CompositorGlobalShortcut` gave way
  to `GlobalShortcut` directly, and the 25 `WM.compositor === "hyprland"`
  branches are gone.
- With them, an entire unreachable sidebar entrance implementation: both
  sidebars defined `animatedEntrance` as permanently false and carried a
  slide-in animation, a delayed-close timer, a full-window mask and a
  click-outside-to-dismiss area behind it. Open/close behavior is
  unchanged — that path never ran.

### Fixed
- The repo-root `VERSION` symlink, which the directory rename left
  dangling.

## [0.6.1] — 2026-07-31

### Fixed
- Quick page: the scheme grid ran a little taller than the wallpaper
  preview. The right column is now height-locked to the preview
  (56px light/dark row + three 66px chip rows + gaps = 280), and the
  palette circles were re-proportioned (34px slot, tighter label gap) so
  the shorter chips keep even outer padding.

## [0.6.0] — 2026-07-31

### Added
- Snagit-style **annotation bar** on region screenshots: releasing a
  rectangular Copy selection now pauses on an Annotate phase with a
  toolbar under the region - draw (freehand), arrow, box and ellipse
  tools, six colors, three stroke widths, undo and clear - then Copy
  (Enter) or Cancel (Esc). Annotated snips are composited at native
  resolution via grabToImage and go through the observable copy pipeline
  (clipboard + screenshot popup); an untouched selection falls back to
  the original lossless magick crop. Right-click edit, circle mode, OCR/
  Lens/QR and recordings keep their instant flows.

### Added
- Per-plugin **"Keep settings across presets"** toggle (pin switch at the
  top of every plugin's options): a flagged plugin's options, desktop
  positions and enabled state survive preset application; the flag itself
  is never captured into presets. Covered by an end-to-end presets.sh
  behavior test.

### Fixed
- Bar/overlay-only plugins (Discord Voice, Docker) no longer show a dead
  "Blur background" toggle - host blur is a desktop-widget mechanism, so
  the injected row now appears only for plugins with a `desktopWidget`
  entry point.

### Changed
- Drop Shelf and Screenshot Result are core shell modules again, not
  bundled plugins: always loaded by the panel family, options in the shell
  config (`dropShelf.*` with the blur knobs, `screenshotResult.*`) and in
  Settings (Drop shelf under Sidebars & Panels; Screenshot popup was
  already under Capture). Plugin-state options migrate is manual-free: the
  live install's preferences were carried over. `PluginPanelHost` stays
  for third-party panel plugins.

## [0.5.1] — 2026-07-31

### Fixed
- Super+Alt+Space (float toggle) also switched the keyboard layout when the
  Settings' layout-switch shortcut was set to Super+Space: xkb `grp:`
  toggles fire even with extra modifiers held. The Super+Space layout
  switch is now a real compositor bind in keybinds.lua (exact modifier
  matching, no-op with a single layout), and the Settings selector no
  longer offers the colliding xkb value - it is relabeled "Extra layout
  switch (xkb)" with only None/Alt+Shift left.

## [0.5.0] — 2026-07-31

### Changed
- Settings reorganized domain-first (per `docs/settings-ux-research.md`,
  Option A). The "Interface" junk-drawer page is gone; every section moved
  to a concrete home, none were altered:
  - **Appearance**: Icon pack, Fonts, Terminal (incl. background image),
    Color generation
  - **Wallpaper & Desktop** (was Desktop): + Wallpaper selector
  - **Bar & Dock** (was Bar): + Dock; − Notifications
  - **Sidebars & Panels** (new): both sidebars + quick toggles/sliders/
    corner-open (from General), Overview, Overlay/Crosshair/Floating
    image, On-screen display (from Interface)
  - **Notifications** (new): promoted out of Bar
  - **Lock & Idle** (new): Lock screen, Screensaver, Keep awake (from
    Interface), Work safety (from General)
  - **Capture** (new): Screen recorder + Instant replay, Save paths (from
    Services), Screenshot popup, Region selector (from Interface)
  - **Services** keeps only the outward-facing ones: AI, Networking,
    Music recognition, Search, Updates, Weather
  - **General** keeps the true globals: Time, Battery, Audio, Sounds,
    Language. Quick is unchanged.
  The nav search metadata is now generated from the pages' actual section
  titles, and the navigation test's page map covers all 13 pages.

## [0.4.0] — 2026-07-31

### Fixed
- Privacy pill named Electron apps "Chromium" (Vesktop's mic use showed as
  Chromium): when a stream's `application.name` is a known-generic
  Electron/WebRTC alias, the capitalized `application.process.binary`
  (e.g. "Vesktop") is shown instead - specific names like "OBS Studio"
  still win. Applied to both the JSON and legacy-text pactl parsers and
  the byte-synced test double.

### Removed
- All Niri compositor support from the upstream merge - this fork targets
  Hyprland exclusively. Deleted: NiriBackend/NiriXkb/NiriConfig services,
  the Niri settings page, NiriBackdrop, the niri monitor-config model, and
  every `WM.compositor === "niri"` branch (session actions, lock, night
  light's wlsunset path, workspace model, wallpaper selector, sidebar
  reload, settings gates, record.sh). Upstream's `WM` and
  `CompositorGlobalShortcut` remain as thin Hyprland-only facades so the
  30+ consumer files stay merge-compatible with upstream. The "Niri Like"
  overview *style* (a layout option on Hyprland) is unrelated and kept.
  SystemTheming (orphaned by the Niri page removal) and FastBlurred
  (unreferenced) removed too.

### Added
- Upstream merge (`pctrade/end4-pC`, decrypted from commits `ns`/`cf`/`nl`/
  `lw`x2 + PR #27):
  - **Niri compositor support**: a `WM` abstraction service (compositor
    detection, workspaces, windows, shortcuts) with `HyprlandBackend`/
    `NiriBackend`, `CompositorGlobalShortcut` wrapper, `NiriXkb`, a Niri
    settings page (config editing via `niri msg`), `NiriBackdrop`, and
    niri-gated behaviors (lock wallpaper/overview disabled, wlsunset night
    light, workspace model branching, logout via `niri msg action quit`).
    The Hyprland/Niri settings pages are now pushed compositor-gated into
    the (still section-annotated) pages list.
  - Bar M3 clock pill: robust against locales/formats with seconds
    (splits on am/pm markers instead of fixed part positions) - PR #27 by
    Reazndev.
  - Night light rework adopted: on startup the service syncs with what is
    actually running instead of force-enabling inside the night window;
    our cold-start launch-flags fix is re-grafted on top.
  - Background clock quote now only shows for pixel/cookie clock styles.
  - Discarded: upstream's full clipboard wipe (would destroy our pinned
    entries - our pins-aware wipe stays), upstream's lock workspace-move
    niri gating (our lock pushes content visually and never touches
    compositor workspaces), upstream's removal of the VPN/Tailscale quick
    toggles. Upstream literals tokenized onto the spacing scale per merge
    policy; record.sh's monitor detection gained the niri branch inside
    our gpu-screen-recorder implementation.

## [0.3.1] — 2026-07-31

### Fixed
- Session screen: "Reboot into..." was unreachable by keyboard (no
  downward path led to it) and sat orphaned on its own row. The grid is
  now a symmetric 3x3 - session actions on top, power actions
  (Shutdown / Reboot / Reboot into...) on the bottom row - with a full
  arrow-key navigation map. The boot-entry pills themselves are now
  keyboard-navigable too, and the picker was restyled twice over: entries
  now stack under the grid clamped to its width (the pill row overflowed
  sideways), Down walks the list / Up returns to "Reboot into...", the
  focused entry fills primary (the current OS stays tonal), Enter reboots
  into it, and the opener button shows a toggled state while open.

## [0.3.0] — 2026-07-31

### Added
- **Selective EFI reboot** in the session screen: a "Reboot into..." action
  (shown only when the firmware exposes more than one permanent boot entry)
  expands a picker of EFI boot entries - transient USB/CD/network entries
  filtered out, current entry marked - and picking one sets `BootNext` via
  `pkexec efibootmgr -n` (polkit prompt) before rebooting straight into
  that OS. Firmware-level, so it works with GRUB, systemd-boot and Windows
  Boot Manager alike; parser covered by node-executed contract tests.
- **Plymouth boot splash** (opt-in installer component, Arch/mkinitcpio):
  a minimal Material-style theme (`sdata/plymouth-theme/immaterial-impulse`)
  with the suite wordmark, a rotating arc spinner, and a text-free LUKS
  password prompt (lock glyph + bullets - no fragile label-plugin dependency
  inside the initramfs). `setup` gains a PLYMOUTH component /
  `INSTALL_PLYMOUTH=1`: installs plymouth, copies the theme, adds the
  mkinitcpio hook (with backup and self-restore), and rebuilds the
  initramfs; the kernel-cmdline `quiet splash` change is printed, never
  auto-applied.

### Changed
- Scheme picker chips preview the colors they would apply, Android-12
  style: a new `scheme_preview.py` quantizes the current wallpaper once
  and derives primary/secondary/tertiary swatches for every Material
  scheme variant (~0.2 s in the color venv); each chip renders them as a
  segmented palette circle (top half primary, quarters secondary/
  tertiary) with the full scheme name below and a ring + check badge on
  the selected one. Refreshed on wallpaper and dark/light changes; falls
  back to the scheme icon when the venv is unavailable.
- Quick settings' Wallpaper & Colors section restyled: scheme chips are
  uniform tonal cards with centered icon+label (no more diagonal
  icon/label scatter), selection animates color and relaxes into a pill,
  the Light/Dark pair matches the same container family with horizontal
  content, and the cramped 2px gaps grew into the spacing scale.
- Screen recorder rebuilt on **gpu-screen-recorder** (GPU encode - NVENC/VAAPI,
  ShadowPlay-style), replacing wf-recorder's CPU x264 path:
  - Same interfaces as before (bar record button, region-selector record
    actions, `Super+Shift+R` / `Ctrl+Alt+R` binds, `record.sh --region/
    --fullscreen/--sound/--path`), now driven by config: quality preset,
    codec (auto/H.264/HEVC/AV1), FPS, framerate mode, cursor, desktop audio
    and optional mic merge - all in Settings → Services → Screen recorder.
  - **Instant replay** (`ScreenRecord` service): a persistent ring-buffer
    daemon keeps the last N seconds (default 120, RAM or disk); save a clip
    with `Alt+F10`, the bar button that appears while replay is armed, or
    `qs -c imi ipc call record replaySave`; toggle with `Shift+Alt+F10`, the
    settings switch, or IPC. Enablement is persisted config, so replay
    survives restarts; a failing daemon disables itself instead of
    respawn-looping.
  - Recording pause/resume (`Ctrl+Alt+R` family unchanged; pause via
    `quickshell:screenRecordPause` global or `record pause` IPC, SIGUSR2).
  - One-shot recordings and the replay daemon are separate gsr processes;
    the record toggle and pause are pidfile-scoped so they can never kill
    the replay buffer. Saved-file notifications come from gsr's `-sc` hook
    with the real path (replay clips included).
  - Suite dependency lists switched from `wf-recorder` to
    `gpu-screen-recorder` (arch/fedora/gentoo/nix).
  - The bar's privacy pill now also shows shell-owned captures: a
    `screen_record` icon while a recording runs (with pause state in the
    hover popup) and a `replay` icon while the instant-replay buffer is
    armed. An **Instant replay** quick toggle joins both right-sidebar
    styles (Android grid: drag it in from the unused set; classic panel:
    always present) - toggle to arm, long-press to save a clip.

## [0.2.0] — 2026-07-31

### Fixed
- Selected icon pack reset by "Update Dots": the dots sync ships a
  `kdeglobals` with `[Icons] Theme=breeze-dark`, overwriting the theme the
  user picked in Settings → Interface → Icon pack (the selection itself
  survives in the shell config; it just never got re-applied). The installer
  now re-applies `appearance.iconTheme` via `apply-icon-theme.sh` after
  every file sync, best-effort.
- About page PC-spec cards stuck on "Loading..." until visiting another
  section: the specs refresh fired on a hardcoded page index (7) that went
  stale when the Plugins page shifted About to 8. The trigger now targets
  the last page by position, and a test pins SettingsContent against
  hardcoded `currentPage` indexes.
- Broken icons (raw "VIDEO_TE□LATE"-style ligature text) in the desktop menu's
  Live Wallpaper entry, the live-wallpaper folder setting and the sidebar
  settings' Media Player card: the SDDM theme ships an older Material Symbols
  Rounded copy that fontconfig can pick over the system font, and it predates
  the `video_template`/`music_note_2` names. Renamed to `animated_images` /
  `music_note`, and a new lint (`tests/lint_material_icons.py`) validates
  every literal icon name against the GSUB ligatures of EVERY installed copy
  of the font so stale-font breakage can't sneak back in.

### Added
- About page "What's new" card: renders the changelog of the installed suite
  checkout (`~/.local/share/immaterial-impulse/src/CHANGELOG.md`, the copy
  get.sh refreshes on Update Dots) as collapsible Markdown, bounded to the
  newest two sections, with a Full-changelog link to GitHub. Hidden when the
  checkout or file is absent.
- Drop Shelf is now a bundled **plugin** (`drop_shelf`, enabled by default)
  with Dropover-style summoning (see `docs/dropshelf-shake-research.md`):
  - **Mid-drag summon**: `Super+U` (Hyprland `quickshell:dropShelfSummon`
    global shortcut) or `qs -c imi ipc call dropShelf toggle` opens the shelf
    under the cursor — works while dragging files, so the in-flight drag can
    be dropped straight onto it.
  - **Drag-to-bar reveal**: dragging files onto the bar pops the shelf out
    below it (the Wayland-native trigger — a `DropArea` learns of a drag the
    moment it crosses a shell surface); dropping on the bar itself also
    stashes the files.
  - **Shake to summon** (opt-off by default): a helper polls the Hyprland
    request socket (raw socket, ~0.03 ms/query at 60 Hz) and recognizes
    ≥3 fast horizontal direction reversals with extrema-based leg tracking
    (`scripts/dropshelf/shake_detector.py`, pure-logic detector covered by
    `tests/test_dropshelf_summon.py`). Paused while locked or a fullscreen
    app is focused. Wayland offers no global "drag in progress" signal, but
    every pointer drag holds the primary button — the gesture is armed only
    while BTN_LEFT is down (global state read via the `EVIOCGKEY` evdev
    ioctl; needs `input`-group membership, degrades to always-armed
    without it), so shaking a free cursor does nothing.
  - A summoned shelf **auto-dismisses** (default 5 s, configurable) unless
    hovered, dropped on, or holding items.
  - **Blur-able background**: the shelf tint's opacity is configurable and
    the compositor blurs behind every `quickshell:*` layer, so lowering it
    frosts the shelf; both knobs live in the plugin's settings along with
    bar-reveal, shake, sensitivity and auto-dismiss options.
  - The desktop-menu "DropShelf" entry and the bar reveal hide when the
    plugin is disabled; the shelf window is created lazily on open.
- Discord voice: one-shot companion installer
  (`scripts/discordVoice/install_companion.sh`) — auto-detects Vesktop and
  Equibop (`--client` to pick), clones and builds the matching mod (Vencord /
  Equicord, same plugin API) with the End4DiscordVoice user plugin, and
  points the client's custom-mod location at the build (backing up
  `state.json` first). The Discord Voice popup gains a one-click **Install
  voice companion** button that runs the installer and streams its progress
  whenever the bridge reports the companion is missing; the bridge error
  also names the script. Official Discord still needs nothing; Legcord
  remains unsupported (bundled Vencord, no custom-location picker).
- Upstream merge (`pctrade/end4-pC`):
  - Desktop Notes widget: a flip-card notes list on the background (add, edit,
    swipe to delete; persisted in the shell state dir), toggle in
    Settings → Background widgets.
  - Live wallpaper preview (opt-in via `background.enableWallpaperPreview`):
    single-click or arrow-key navigation previews the wallpaper on the real
    background, double-click applies; preset apply clears any pending preview.
  - Dock-to-panel bar widget: drag-to-reorder pinned apps with animated slot
    translation.
  - Dock: the pinned-apps section and its separators hide when nothing is
    pinned; drag-ghost polish.
  - Screenshot while recording snips via plain grim+slurp instead of the
    region-selector UI (which doubles as the recording control), and the record
    keybind now stops a running recording. (Hardened over upstream: the save
    directory is passed as an argv element instead of interpolated shell text.)
  - Bar settings: the divider space-width spinbox is only enabled for the
    "space" divider style.
- Upstream feature sweep (first batch, from the `end-4/dots-hyprland` tracker):
  - GPU usage/temperature now works on AMD/Intel too (hwmon/sysfs fallback);
    the NVIDIA path is unchanged.
  - Bluetooth connect/disconnect button shows a "Connecting…"/"Disconnecting…"
    pending state while the operation is in flight.
  - Bluetooth device battery (upstream PR #3538): the quick-toggle tile status
    and tooltips now show the connected device's battery percentage (when the
    device reports one), matching the device-list dialog.
  - Calendar: configurable first day of week (Monday/Saturday/Sunday).
  - Bar: option to show only the current monitor's workspaces
    (`bar.workspaces.showAllMonitors`).
  - Weather: provider choice (OpenWeatherMap or keyless wttr.in) and a
    user-settable OWM API key (falls back to the built-in key when empty).
  - Caps Lock / Num Lock on-screen display (toggle: `osd.lockKeys`).
  - Clipboard pinning: pin entries so they stay on top and survive "wipe all".
  - Clipboard clear buttons (upstream PR #3546): the launcher's clipboard view
    gains a header with "Clear results" (deletes only the entries matching the
    current filter) and "Clear all" buttons, plus an empty-state hint; both
    respect pinned entries, and deletions go to `cliphist delete` over stdin.
  - File/folder search in the launcher (`~`-prefixed query, fd/find backed).
  - Lock screen: previous/play-pause/next controls on the media widget.
  - OLED screensaver (Settings → Interface): idle overlay with a full-black or
    a slowly-drifting dim clock mode; off by default.
  - NetworkManager VPN toggles in the right sidebar plus a bar status icon.
  - Automatic dark/light theme switching by time — sunrise/sunset or fixed
    times (Settings → Wallpaper & Colors); off by default.
  - ICS calendar: load events from local `.ics` files and remote ICS URLs and
    mark days that have events in the sidebar calendar.
  - Bar "Timer" pill (add via Settings → Bar): a dynamic-island pill showing a
    running pomodoro/stopwatch, opening the sidebar on click.
  - Privacy indicator (in the default right bar): an alert pill that appears
    only while an app is using the microphone, camera, or sharing/recording the
    screen, listing the source in a hover popup. Each signal's icon and the pill
    ease in and out.
  - Notes plugin (bundled desktop widget): a persistent, autosaving notepad
    that shares the notes scratchpad with the overlay notes editor.
  - Hyprland submap indicator (upstream PR #2225, in the default right bar): a
    pill with a keyboard icon and the submap name that appears while a keybind
    submap (e.g. resize) is active and eases out when it resets; icon-only in
    the vertical bar. Tracked by the new `HyprlandSubmap` service.
  - Dock: right-click context menu on app icons (upstream PR #3045) —
    desktop-entry actions (e.g. "New Window"), open new instance, move all of
    an app's windows to a workspace, pin/unpin, and close window(s). Window
    previews are suppressed and the dock stays revealed while the menu is open.
    (Drag-to-reorder of pinned apps, the PR's other half, already exists here.)
  - Tailscale (upstream PR #3501, reworked for the sidebar): a quick toggle
    next to the VPN toggles (both classic and Android styles) that brings
    Tailscale up/down, plus an exit-node dialog (right-click / tile menu)
    listing peers that advertise themselves as exit nodes — online first, with
    a "None (direct)" row — applied via `tailscale set --exit-node=…` with a
    one-shot `pkexec` fallback for non-operator users. Backed by the new
    `Tailscale` service polling `tailscale status --json`; hidden entirely
    when the CLI isn't installed.
  - OpenRGB accent sync (upstream PR #3415, reworked as a plain CLI call): an
    opt-in toggle (Settings → Quick) that applies the Material You accent
    color to RGB hardware whenever the palette changes, debounced, via
    `openrgb --mode static`; silently inert when the binary is missing.
    Individual devices can be excluded from the sync with per-device switches
    under the toggle (`appearance.openrgb.excludedDevices`, keyed by device
    name so paired hardware like RAM sticks toggles as one).
    An optional ambient mode (`appearance.openrgb.colorSource: "monitor"`)
    instead follows the focused monitor's dominant on-screen color — by
    default only while a fullscreen app runs (games, video), snapping back to
    the accent on exit. Sampling is a low-rate grim capture reduced by
    Quickshell's ColorQuantizer, with a deadband and optional smoothing so
    near-static scenes produce no device writes; needs `grim`, silently inert
    without it. The shell manages an `openrgb --server` for the streaming
    writes (serverless CLI calls re-detect hardware every time, resetting
    devices to white), and excluded devices are kept out of OpenRGB's own
    detector list so the server never claims them — a claimed device loses
    its firmware lighting even without a single color write. GPU lighting is
    excluded from ambient writes by default (`monitorExcludedTypes`): GPU RGB
    rides the graphics i2c bus, and streaming to it mid-game stalls
    rendering; the ambient loop also scans devices once per activation
    instead of before every write. The bar's privacy indicator filters the
    sampler's once-a-second capture pulses (`bar.privacyIndicator.
    ignoreAmbientCapture`, default on) — real screen shares still show, since
    they hold their state past the pulse window.
- Component grid for desktop plugins: formalizes the nandoroid design-system
  grid (a 132×108 cell with a 12px gap) as `Appearance.sizes.widgetGridSpanX/Y`
  with an opt-in manifest `grid: { cols, rows }` that sizes a widget to whole
  cells so it tiles flush with the built-in widgets; the Notes widget is now a
  true 2×2 tile (276×228). Documented in `docs/widget-grid.md`.
  - Settings → Plugins now badges third-party (externally installed) plugins.
  - Presets: an Overwrite action on each preset card saves the current setup
    over that preset (two-tap confirm).
- Media plugin: the Next/Previous cog buttons now spin like cassette reels
  while media is playing (both clockwise, icons stay upright), easing back to
  rest on pause.
- Curated default configuration: fresh installs now seed `config.json` from the
  maintainer's tuned setup (sanitized of machine-specific state) instead of the
  bare upstream fallback defaults; existing configs are never touched.
- Icon pack selector (Settings → Interface): preview-grid cards rendering each
  theme's real icons, system-wide apply (GTK 3/4 `settings.ini`, `kdeglobals`,
  gsettings) with validation, and an automatic shell relaunch to adopt the pack.
- Verified-prebuilt Wallpaper Engine install path: on x86_64 the installer
  downloads a checksum-verified release tarball (seconds) and falls back to the
  source build on any mismatch; companion release CI lives in qs-wallpaperengine.
- Quiet-mode install is now cancellable (Ctrl-C cleanly stops the whole build).
- Frost mode toggle (tint vs true blur) for plugin backdrops in Settings → Plugins.
- README: palette showcase screenshots (Green / Study / Red).
- README translations: Simplified Chinese (`README.zh-CN.md`) and Japanese
  (`README.ja.md`), with a language switcher linking all three.
- Dock feedback motion (M3 Expressive): hover lift, press squish, a launch
  bounce that runs until the app's window appears, an appear pop for new
  icons, and springing active-window dots — consistent across pinned and
  running apps, all on Appearance motion tokens.

- Test coverage sweep: 16 new suites covering the installer's destructive
  paths (rsync --delete sandboxing, legacy package removal, cancel traps),
  the color pipeline (lock/desktop palette parity, scheme detection,
  generator goldens), the keybind cheatsheet parser, momentum scrolling,
  and always-on services (Battery, Bluetooth, Updates, Brightness,
  SystemInfo, ConflictKiller, Polkit, Ydotool) - plus three previously
  orphaned suites now actually running in CI.
- Screenshot result popup (bundled plugin): every screenshot - region snip or
  Print keybind - pops a preview with save / annotate / discard actions;
  auto-dismisses, hover pins it. The plugin platform's `panel` entry point is
  now actually instantiated (PluginPanelHost), so plugins can ship
  free-floating surfaces.
- Centered Wallpaper now shows live Wallpaper Engine content inside its shape
  (centre-cropped from the same surface the blur/lock shaders sample, so no
  second renderer), falling back to the static/thumbnail image when no live WE
  surface is drawing.
- Experimental updater (`./setup exp-update`) now reports how many updates are
  available before pulling and prints the new CHANGELOG entries under a
  "What's New" heading after a successful update.
- Plugins settings: each plugin and its options are now one unified rounded
  card (header, hairline divider, then its option toggles as part of the same
  surface) with clear gaps between plugins, and the plugin name is larger and
  heavier so it reads as the card's heading.
- Plugin store (Settings → Plugins → Browse plugins): browse, search, and
  filter a curated catalog of community plugins and install or update them in
  one click through the existing hardened installer. Entries come from a new
  registry repo (`XephyLon/imi-plugin-registry`) whose CI cross-checks each
  entry's metadata against the plugin's actual manifest, so the permissions
  shown in the install confirmation dialog are verified, not self-reported.
  Update badges (semver against the installed version) appear on the Plugins
  page and on installed plugins' cards, with an "Update all" queue in the
  store. The installer gains `--upgrade` (stage, verify, then atomic swap with
  rollback) and writes a `.store.json` provenance sidecar after every install.
  The store UI ships gated off behind `plugins.storeEnabled` (config-file-only,
  default false) until the public registry goes live. Documented in
  `docs/PLUGIN_STORE.md`.

### Fixed
- Bar and dock media widgets broke on Arabic (RTL) track metadata: the text
  auto-aligned to the right edge away from the artwork, and Arabic's taller
  line box overflowed the fixed-height card, clipping the lines top and
  bottom. Text is now left-anchored with fixed, vertically-centered line
  slots so every script lays out like Latin.
- "Keep system awake" sometimes still let the session lock and hibernate: the
  idle inhibitor was bound to a 0×0 surface that maps unreliably, so Hyprland's
  ext-idle-notify (read by hypridle) intermittently ignored it. It now uses a
  reliably-mapped 1×1 transparent background-layer surface.
- Upstream bug sweep (audited `end-4/dots-hyprland`'s tracker against our fork,
  fixed the ones still present):
  - Sidebars/panels no longer "blink" open then instantly shut — a transient
    focus-grab clear from a ToplevelHandle activation is now debounced.
  - Launcher/app search no longer pegs a core: the app list is deduped in O(n)
    instead of O(n²) on every desktop-entry change.
  - Hyprland data refresh is debounced, so spawning apps (e.g. kitty) or fast
    workspace switches no longer stutter the UI by spawning `hyprctl` per event.
  - The battery widget no longer flaps in/out and no longer fires false
    low-battery notifications (or auto-suspend) when UPower transiently swaps its
    display device.
  - A fully-bracketed song title (e.g. `[BLEED BLOOD]`) shows the real title
    instead of "No media".
  - The cheatsheet no longer double-lists a keybind defined in both the default
    and custom Lua configs; custom now overrides default.
  - An offline random-wallpaper fetch can no longer corrupt config by persisting
    a truncated/missing wallpaper path.
  - Base installs (without Wallpaper Engine) now also launch the shell with the
    threaded render loop, so a GPU-saturating process can't freeze it.
  - Notification popups wait a short grace period before hiding on unfocus, so a
    brief cursor flicker no longer dismisses them.
  - With bar auto-hide on, the media box and tray-overflow popup are no longer
    orphaned above a hidden bar (new `bar.autoHide.dismissPopups` option).
  - The screen-corner "absolute corner" hover no longer opens the sidebar when
    "Hover to trigger" is turned off (it is a sub-option of it).
- Experimental updater failed to detect/report updates that existed: its change
  detection keyed off the reflog's `HEAD@{1}`, which a preceding stash or
  detached-HEAD checkout silently repointed. It now captures a stable pre-pull
  baseline SHA and counts incoming commits straight from refs (`git fetch` +
  `git rev-list --count`).
- Terminal background settings note that the pattern applies to the Kitty
  terminal only.
- Lock-screen palette could differ from the desktop's for the same image: lock
  color generation passed `--smart` (silently swapping the configured scheme to
  neutral on low-chroma images) and hardcoded tonal-spot for `auto` instead of
  running the same image-based detection as the desktop.
- Wallpaper Engine wallpapers were permanently mute: the embedded renderer
  hardcoded `--silent` and the selector's volume button toggled a flag nothing
  read. The button now drives the new `audioEnabled` surface property (toggling
  reloads the wallpaper - audio is a load-time decision inside WE).
- Multi-second shell freezes on wallpaper/preset switches, root-caused to three
  compounding issues: Qt's basic render loop on NVIDIA/Wayland blocking the GUI
  thread on embedded-WE video GL (fixed via `QSG_RENDER_LOOP=threaded` in the WE
  wrapper); kde-material-you re-applying the unchanged icon theme every switch
  (dropped `iconslight`/`iconsdark`); and Quickshell rescanning every `.desktop`
  file on any parent-directory churn, stalling the UI in multi-second QML GC
  pauses (patched in qs-wallpaperengine's bundled Quickshell). Cycling all four
  presets went from 11 UI stalls (up to ~4.8 s) to none.
- MPRIS artwork, favicon, weather, wallpaper-download and AI-request fetches no
  longer splice external values into `bash -c` strings (command-injection
  hardening; values now passed as arguments).
- Cookie clock (and other draggable desktop widgets) follow preset position
  changes again instead of ignoring them or snapping back while dragging.

## [0.1.0] — 2026-07-23

First versioned release of the unified suite (the `Immaterial Impulse` fork of
illogical-impulse), collecting the work done to date:

### Added
- Unified repo: the Quickshell shell, full Hyprland config, and a `whiptail`
  installer in one tree, superseding a prior illogical-impulse install (with
  first-run config-dir + keyring migration).
- Optional installer components: Wallpaper Engine (custom Quickshell build) and
  the `ii-sddm-theme` SDDM login theme.
- Plugin platform (declarative + package plugins), Material You theming extended
  to cava/tmux, and the Caelestia animation preset.
- Wallpaper Engine wallpaper picker with type-filter chips.
- Automatic Hyprland animation-preset loading; restored keybind cheatsheet
  (`Super`+`/`).
- This changelog and versioning.

[Unreleased]: https://github.com/XephyLon/immaterial-impulse/compare/v0.32.0...HEAD
[0.32.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.31.2...v0.32.0
[0.31.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.31.1...v0.31.2
[0.31.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.31.0...v0.31.1
[0.31.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.30.2...v0.31.0
[0.30.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.30.1...v0.30.2
[0.30.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.24.0...v0.25.0
[0.24.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.23.1...v0.24.0
[0.23.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.20.1...v0.21.0
[0.20.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.20.0...v0.20.1
[0.20.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.18.2...v0.19.0
[0.18.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.18.1...v0.18.2
[0.18.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.6...v0.18.0
[0.17.6]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.5...v0.17.6
[0.17.5]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.4...v0.17.5
[0.17.4]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.3...v0.17.4
[0.17.3]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.2...v0.17.3
[0.17.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.1...v0.17.2
[0.17.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.17.0...v0.17.1
[0.17.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.16.1...v0.17.0
[0.16.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.16.0...v0.16.1
[0.16.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.9...v0.15.0
[0.14.9]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.8...v0.14.9
[0.14.8]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.7...v0.14.8
[0.14.7]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.6...v0.14.7
[0.14.6]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.5...v0.14.6
[0.14.5]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.4...v0.14.5
[0.14.4]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.3...v0.14.4
[0.14.3]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.2...v0.14.3
[0.14.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.1...v0.14.2
[0.14.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.11.0...v0.13.0
[0.11.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/XephyLon/immaterial-impulse/releases/tag/v0.1.0
