# Licenses

This repository contains code from other repositories. Files containing such code should include a license notice, and a copy should be stored in this folder.

| File | Source | License |
|---|---|---|
| `dots/.config/quickshell/imi/modules/imi/dock/shaders/split.frag` | Adapted from `assets/shaders/keystone/frag/pill_morph.frag` in [StatIndet/quickshell](https://github.com/StatIndet/quickshell) (Clavis, by StatIndet; no copyright line in the file) at 5183553. The uniform-driven structure and the distance pair - upstream's `roundedBoxDistance` and `smoothMinimum`, here `roundedBox` and `smoothMinimum` - are rewritten from it: the rounded box takes a radius per corner, the second body is a half-plane, and the blend tapers and is covered by the field's gradient. Those two functions are Inigo Quilez's published formulas (iquilezles.org, "2D distance functions" and "smooth minimum"), which Clavis also uses. | GPL-3.0-or-later upstream (Clavis's packaging); used here under GPL-3.0, this repository's own license (`GPL-3.0.txt`) |
