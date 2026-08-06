# Proposal: close the remaining rich-text injection sites for plugin manifests

> **Implemented** (branch `proposal/manifest-rich-text-hardening`), taking the
> recommended shape — flip the default rather than enumerate a sixth and
> seventh site:
>
> - `StyledText` (both copies) now defaults `textFormat` to `Text.PlainText`;
>   rich text is a per-site opt-in. The sweep for implicit `AutoText`
>   dependents found exactly two, both now explicit
>   (d782c2170, "fix(widgets): default StyledText to PlainText, make rich
>   text opt-in").
> - The "unverified lead" below verified real: the Basic Controls style draws
>   `placeholderText` through its own `AutoText` `Text`, out of the default's
>   reach, so `ConfigTextArea` pins it at completion (dce31aa98,
>   "fix(widgets): force ConfigTextArea's style placeholder to plain text").
> - The adjacent registry drift is fixed and the two vocabularies pinned
>   together by the suite (6a359273a, "fix(plugins): require a screenshot for
>   overlay-widget registry entries").
> - The lint the recommendation asked for exists:
>   `tests/lint_rich_text_optin.py` pins the PlainText default, a reviewed
>   opt-in allowlist in both directions, and the placeholder guard
>   (f224ec6b7, "test(lint): pin the PlainText default and reviewed rich-text
>   opt-ins").
>
> The body below is the proposal as parked, kept for the reasoning.

## Goal

Finish hardening the settings UI against **installed plugin manifests**, which
are attacker-controlled. Two render sites were fixed on the Widgets-page branch;
five more remain, plus a validator that never sanitises.

## The mechanism

`StyledText` is a bare `Text` and sets no `textFormat`, so it inherits Qt's
default `Text.AutoText` — which auto-detects and renders HTML-like markup. Any
`StyledText` displaying a manifest-derived string renders `<img src=…>` as
markup rather than as text.

`PluginValidator.js` type-checks `manifest.name` and nothing more. There is no
sanitisation anywhere, so **the render site is the only defence**.

## Already fixed (v0.10.0+, `feat/widgets-page-ia`)

- `ConfigSwitch.qml` — the label and description, which is how the Widgets page
  renders every manifest's `name`, `description`, `author` and `version`.
- `MaterialSymbol.qml` — icon ligature names. `PluginOptions.qml:70,98,119`
  feeds it `optionData.icon` straight from the manifest, so this was an open
  path *inside* the widget the first fix had just closed.

## Remaining sites

All five verified against the source; each is a bare `StyledText` with no
`textFormat`, reachable from manifest data.

| Site | Reached from |
|---|---|
| `modules/common/widgets/GroupButton.qml:138` | `BarConfig.qml:44` (`name: plugin.name`) → `getWidgetName()` → `LayoutSection.qml:44` `buttonText`. Also `ConfigSelectionArray.qml:73` `buttonText: modelData.displayName`, from manifest `choices` via `PluginOptions.qml:86`. |
| `modules/common/widgets/WindowDialogParagraph.qml:7` | `PluginUninstallDialog.qml:27-30`, `.arg(root.pluginName)` where `pluginName` is the manifest `name`. |
| `modules/common/widgets/ConfigSelectionArray.qml:39` | `PluginOptions.qml:84` (`optionData.label`) |
| `modules/common/widgets/ConfigSlider.qml:33` | `PluginOptions.qml:96` |
| `modules/common/widgets/ConfigTextArea.qml:59,65` | `PluginOptions.qml:120` |

Note the asymmetry worth fixing on its own merits: `PluginInstallDialog.qml`
already holds the PlainText contract (lines 13, 57, 87, 100), while its sibling
`PluginUninstallDialog.qml` holds none. That looks like an oversight rather than
a decision.

Unverified lead: `ConfigTextArea.qml:15` aliases `placeholderText` to the inner
field, and `PluginOptions.qml:121` feeds it `optionData.placeholder`. Whether
the Controls style renders a placeholder through an `AutoText` `Text` needs
checking before filing it as a site.

## Approach

Two candidate shapes, and they are not equivalent:

- **Per-site** — add `textFormat: Text.PlainText` at each of the five. Smallest
  diff, no behaviour change anywhere else, but it is the sixth time this fix has
  been applied one site at a time, and the `MaterialSymbol` case shows how
  easily the next one is missed.
- **Flip the default** — give `StyledText` itself `textFormat: Text.PlainText`
  and have the handful of sites that genuinely want markup opt in. Four already
  opt in explicitly (`NotificationItem.qml:174`, `NotificationPopupItem.qml:198`,
  `WeatherCard.qml:192`, and one more), which is evidence the codebase already
  treats rich text as the exception. This closes the whole class instead of
  enumerating it, at the cost of a wide blast radius that needs a careful sweep
  for sites relying on `AutoText` implicitly.

Recommendation: flip the default, with the per-site fix as the fallback if the
sweep turns up implicit dependents. A lint pinning that new `StyledText` render
sites for untrusted data cannot regress would be better than either.

## Adjacent: the same vocabulary drift, a third time

`scripts/plugins/registry_validate.py:36` defines
`VISUAL_CAPABILITIES = frozenset({"desktop-widget", "bar-widget", "panel"})` —
missing `overlay-widget`. A registry entry declaring only that capability
escapes the "a visual capability requires a screenshot" check.

This is the same drift the Widgets-page work removed from the QML side by moving
the vocabulary into `PluginManager.surfaceCapabilities`. The Python validator is
a separate copy that nothing keeps in sync, and it is now the only remaining one.

## Out of scope

- Sanitising manifest strings at parse time. The render site is the right place;
  stripping markup on the way in would corrupt legitimate text containing `<`.
- Any change to what plugins are permitted to declare.
