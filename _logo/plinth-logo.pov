// ---------------------------------------------------------------------------
// Plinth wordmark -- "PLINTH" as beveled 3D letters standing on a studio
// floor, in the spirit of the Pixar wordmark. The I is a plinth in miniature,
// which is the mark already used as the project's favicon: a white pedestal
// on a coral tile.
//
// Render:
//   povray +Iplinth-logo.pov +Oplinth-logo.png +W1800 +H700 +A0.25 +AM2 +R3 +Q11
//
//   povray +Iplinth-logo.pov +Oplinth-dark.png Declare=Theme=1 \
//          +W1800 +H700 +A0.25 +AM2 +R3 +Q11
//
// The camera angle is tuned for that 1800x700 frame: POV-Ray widens the real
// field of view along with the "right" vector, so a different aspect ratio
// needs "angle" retuned (larger angle = wider frame = smaller wordmark).
//
// Options (add on the command line):
//   Declare=Motif=0   plain letters instead of the plinth-shaped I
//   Declare=Theme=1   white letters on a dark ground, coral plinth
// ---------------------------------------------------------------------------

#include "plinth-common.inc"

// ---------------------------------------------------------------------------
// The word
// ---------------------------------------------------------------------------
#declare Word =
union {
  #declare Cur = -TotW / 2;
  #declare i = 0;
  #while (i < NC)
    #if (Motif = 1 & i = 2)
      object {
        PlinthColumn(ColW, Thick, 1)
        translate x * (Cur + Wid[2] / 2)
        texture { T_Column }
      }
    #else
      object {
        Beveled(Chars[i])
        translate x * (Cur + Wid[i] / 2)
        texture { T_Letter }
      }
    #end
    #declare Cur = Cur + Wid[i] + Trk;
    #declare i = i + 1;
  #end
  interior { ior 1.5 }
  scale Scl
}

StudioFloor(1)
StudioSky()
StudioLights(1)

camera {
  perspective
  // Dead centre in x: the word stays symmetric, and the 10 degrees of
  // elevation is what reveals the tops of the letters. Standing well back with
  // a narrow field keeps the outer letters from splaying the way a wide angle
  // makes them.
  location < 0.0, 6.00, -29.5>
  look_at  < 0.0, 1.15,   0.0>
  right    x * image_width / image_height
  angle 19
}

object { Word }
