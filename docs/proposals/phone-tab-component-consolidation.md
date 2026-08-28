# Consolidating the Phone tab onto the shell's own components

Status: proposed, not started. Queued 2026-08-28. Direction decided by the
maintainer; the scope of what to delete versus keep is still open.

## Why

The Phone tab was built in a day by seven agents working in parallel with
disjoint file ownership. It follows every rule that has a lint behind it —
tokens, motion tiers, glyph alignment, process lifecycle, argv-not-shell —
and breaks the one that does not: **it is assembled from hand-rolled QML
where the shell already ships the component.**

The clearest case is notifications, because the shell's vocabulary was
already complete before the tab existed:

| The shell already had | The tab wrote instead |
|---|---|
| `common/widgets/NotificationGroup.qml` (282) | `sidebarLeft/phone/PhoneNotificationList.qml` (423) |
| `common/widgets/NotificationListView.qml` (68) | — |
| `common/widgets/NotificationAppIcon.qml` (103) | — |
| `sidebarRight/notifications/NotificationList.qml` (121) | `sidebarLeft/phone/PhoneFooterBar.qml` (133) |
| `sidebarRight/notifications/NotificationStatusButton.qml` (45) | — |
| **619 lines** | **556 lines** |

556 lines re-implementing 619 that existed. It is also why the phone
footer's clear button draws its glyph off-centre while the right sidebar's
identical-looking button does not: it is not the same button.

The header comment in `PhoneNotificationList.qml` defends the copy on the
grounds that a phone notification is a public id on a KDE Connect leaf with
a `replyId` and Android action keys, so "teaching one card both models would
put a branch on every line of it." The audit checked: the coupling to
`services/Notifications.qml` in `NotificationGroup` is **six call sites**.
And the swipe gesture — `dragConfirmThreshold`, `dismissOvershoot`, the
neighbour lean, the binding-break — carries no model knowledge at all, and
is now in its fifth copy across the tree.

## What this is not

Not a lint-first job. A check that freezes the duplication in place and
merely stops it growing is the wrong order: the code should not exist. Land
the deletions, then fence the gap over a tree that is already clean.

## Shape

1. **Make the notification components model-agnostic** at those six sites —
   a small adapter (dismiss, reply, invoke action, the group's fields) that
   `services/Notifications.qml` and `services/PhoneNotifications.qml` both
   satisfy. Extract the swipe arithmetic once, the way `layout_ops.js` was
   extracted when four surfaces had each worked out the same reorder.
2. **Delete `PhoneNotificationList.qml` and `PhoneFooterBar.qml`.** The
   misaligned glyph goes away with the file rather than with a nudge.
3. **Work off the rest of the audit's inventory**: `CatalogueRow` bypassed
   six times, `NoticeBox` vs three other error-banner spellings,
   `WindowDialog` vs the hand-rolled `InstallGuidePopup` (which also has no
   entrance, no Escape and the wrong content padding), `FilterChip` vs two
   local chip implementations, `RippleButtonWithIcon` vs nine icon+label
   buttons, and `RippleButton` vs the feature card's `MouseArea` — which is
   why none of the tab's three primary actions is keyboard-reachable.
4. **Then the lint**, as a ratchet: fail on the hand-rolled shapes, over a
   tree with no remaining offenders.

## Sequencing

Four agents are in these files as of writing (roster/footer/Stop, ADB
pairing UI, preview lifetime, scripts). The maintainer's call: let them
finish, then decide what survives. Expect some of their work to be deleted
by this pass rather than merged into it — two of the three UI branches are
fixing files this pass would remove outright.

## The process failure behind it, recorded so the next feature does not repeat it

- The agents were handed the *fork's* file list as the spec, which
  pre-decided a file-for-file port of another shell's widgets.
- The briefs carried token rules and no composition rule. Everything with a
  lint behind it came out clean; the prose rule lost.
- Disjoint file ownership is a merge-safety tool. Used as a design boundary
  it stopped three agents from converging on one error banner.
- The brief for the notification list literally said "reuses
  `NotificationGroup`'s **shape**" — an instruction to copy, not to use.

Standing correction for future UI briefs: name the component inventory, and
require any hand-roll to be justified in the agent's final report.
