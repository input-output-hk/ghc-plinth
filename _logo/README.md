# Logo sources

POV-Ray scenes for the 3D Plinth marks. Underscore-prefixed, so Jekyll does not
copy any of it into the built site.

| File | What |
|---|---|
| `plinth-common.inc` | palette, geometry, materials, light rig -- shared, so the two marks cannot drift apart |
| `plinth-logo.pov` | the PLINTH wordmark |
| `plinth-icon.pov` | the plinth alone on a brand tile, for the favicons |
| `make-icons.py` | rounds the tile corners and cuts the favicon sizes |

Rendering, from this directory:

```sh
# wordmark -> assets/images/plinth-wordmark.png (downscaled to 1200px wide)
povray +Iplinth-logo.pov +Oplinth-logo.png +W1800 +H700 +A0.25 +AM2 +R3 +Q11

# favicons -> assets/
povray +Iplinth-icon.pov +Oplinth-icon.png +W1024 +H1024 +A0.2 +AM2 +R4 +Q11
./make-icons.py plinth-icon.png
```

`Declare=Theme=1` renders either scene white-on-charcoal instead of
coral-on-white. The site is light-skinned, so only the light variants are
committed.

The palette comes from the site's own CSS (`#fc4d50`, `#ffffff`, `#f2f2f2`,
`#222222`). Two things in `plinth-common.inc` are worth reading before changing
the lighting: `Note [sRGB hex under assumed_gamma 1.0]` and
`Note [Hitting the brand colour]` -- the coral albedo is hand-calibrated against
this light rig, and moving the lights invalidates it.

The flat artwork these were matched against is still in the repo and still in
use: `assets/images/favicon-source.svg` (geometry), `_includes/svg/logo.svg`
(24px header mark) and `assets/safari-pinned-tab.svg` (monochrome mask).
