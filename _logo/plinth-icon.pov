// ---------------------------------------------------------------------------
// Plinth icon -- the plinth-shaped I from the wordmark, alone on a flat brand
// tile, lit by the same rig. Square frames only. Feed the render to
// make-icons.py, which rounds the corners and cuts the favicon sizes.
//
// Render:
//   povray +Iplinth-icon.pov +Oplinth-icon.png +W1024 +H1024 +A0.2 +AM2 +R4 +Q11
//
// Options (add on the command line):
//   Declare=Theme=1   coral plinth on a charcoal tile
//   Declare=Fine=1    keep the wordmark's slim transition mouldings
// ---------------------------------------------------------------------------

#include "plinth-common.inc"

#ifndef (Fine)
  #declare Fine = 0;    // see Note [Chunky for the small sizes]
#end

// Note [Chunky for the small sizes]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// The icon plinth is wider and its shaft thicker than the one standing in the
// wordmark, because it no longer has to pass as a capital I in a line of text.
// These are roughly the proportions of the existing flat mark, and they are
// what survives being resampled down to 16 pixels.
#declare IconW = 0.72;    // em, against a height of CapH (~0.72 em)
#declare IconD = 0.42;

// Note [Flat albedo for the icon]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// The wordmark's ceramic darkens towards the base of each letter, which at 16
// pixels turns the plinth's base slab into a grey smudge and costs the mark its
// silhouette. The icon uses one flat albedo instead and lets the lighting do
// all of the shading.
#declare T_Icon = Ceramic(C_Col, C_Col, 0.42)

#declare Icon =
object {
  PlinthColumn(IconW, IconD, Fine)
  texture { T_Icon }
  interior { ior 1.5 }
  scale Scl
}

#declare IconH = CapH * Scl;

// ---------------------------------------------------------------------------
// Note [Flat tile, lit subject]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// The tile has to be the exact brand hex -- an icon is read as a colour swatch
// before it is read as a shape -- so the backdrop is a self-emitting plane
// rather than a lit surface: emission carries the pigment straight to the film
// with no shading and no need for the compensation in Note [Hitting the brand
// colour]. It is no_shadow so the lights behind it still reach the subject, and
// the studio floor stays no_image so it bounces light up into the base without
// appearing in frame or planting a shadow on the tile.
// ---------------------------------------------------------------------------
plane {
  z, 9
  pigment { #if (Theme = 0) C_Coral #else C_Ink #end }
  finish { emission 1 diffuse 0 }
  no_shadow
  no_reflection
}

// Note [The dark tile runs a little dark]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// On the charcoal tile the coral plinth renders #e5494a against the brand
// #fc4d50: right hue, ~9% short on red. The albedo is already at full red (see
// Note [Hitting the brand colour]) and the emissive tile gives back no bounce,
// so the only lever left is a hotter key -- which clips red instead of raising
// it and washes the hue out to #ff6d6d. Left as is; the light tile, where the
// coral is a flat fill, is exact.
StudioFloor(0)
StudioSky()
StudioLights(0.35)

camera {
  perspective
  // Only 5 degrees of elevation: any more and the top of the cap turns into a
  // tabletop and the mark stops reading as a letter I.
  location <0, IconH * 0.5 + 1.05, -11.70>
  // Aimed a hair below the middle of the mark: looking slightly down makes it
  // sit high in the frame otherwise, and an icon has to be optically centred.
  look_at  <0, IconH * 0.5 - 0.04,   0.00>
  // Note [Framing a square by hand]
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // "angle" is measured against the right vector, so its effect shifts with
  // the aspect ratio (the wordmark had to be tuned by eye). Giving right, up
  // and direction explicitly makes the field exact instead: the half-angle is
  // atan(0.5 / |direction|), so 5.44 covers 2.15 units at this distance, which
  // leaves the 1.72-unit plinth filling 80% of the tile -- as much of it as the
  // existing flat mark fills, which is what makes it hold up at 16 pixels.
  right     x
  up        y
  direction z * 5.44
}

object { Icon }
