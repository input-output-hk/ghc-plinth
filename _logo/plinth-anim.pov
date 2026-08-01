// ---------------------------------------------------------------------------
// Plinth wordmark, animated -- the letters drop onto the studio floor and
// settle, the plinth-shaped I lands last, and the camera eases back to the
// exact framing of the committed still. Plays once.
//
// Render (from this directory):
//   ./make-anim.sh
//
// or by hand:
//   povray anim.ini
//
// Note [The last frame is the still]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Every animated quantity reaches its final value before clock = 1 and holds:
// the last letter lands at 0.82 and the camera arrives at CamEase. The tail is
// therefore a run of identical frames matching plinth-logo.pov, which is what
// lets index.md offer the committed assets/images/plinth-wordmark.png as the
// reduced-motion alternative without a visible jump. Anything added here must
// keep that property -- `./make-anim.sh --check` tests it.
//
// Options (add on the command line):
//   Declare=Motif=0   plain letters instead of the plinth-shaped I
//   Declare=Theme=1   white letters on a dark ground, coral plinth
// ---------------------------------------------------------------------------

#include "plinth-common.inc"

// ---------------------------------------------------------------------------
// Note [Timeline]
// ~~~~~~~~~~~~~~~
// clock runs 0 -> 1 over the whole animation. Each letter gets a slot, and the
// slots are staggered by Stag, so the word assembles left to right except for
// the plinth, which is dealt the last slot however wide the word is:
//
//   P  |####----------------|
//   L    |####--------------|
//   N      |####------------|
//   T        |####----------|
//   H          |####--------|
//   I            |######----|      <- slower, and no bounce
//                          ^ everything at rest from here to clock 1
//
// The numbers put the last landing at clock 0.82: late enough that the drops
// are not rushed, early enough to leave half a second of still tail (see
// Note [The last frame is the still]).
// ---------------------------------------------------------------------------
#declare Stag    = 0.095;   // clock between one letter landing and the next
#declare Dur     = 0.42;    // one letter's whole drop, in clock
#declare DurCol  = 0.52;    // the plinth takes longer -- it is heavier
#declare CamEase = 0.88;    // camera has arrived by this point on the clock

// Note [Hiding a letter before it falls]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// A letter waiting for its slot is left out of the union (On, below) rather than
// parked above the frame. Parking it is visible twice over: in shot it hangs
// clipped along the top edge and gives the reveal away, and even out of shot it
// still casts a shadow -- the key light is high front-left, so a letter held
// above the frame lays a soft smudge across the empty floor, cast by nothing the
// viewer can see.
//
// That shadow is also why each letter is released from as low as it can be and
// still be hidden: it is an unexplained smudge until it enters, so that window
// wants to be a frame or two. The lowest safe height moves as the camera
// narrows -- the top edge of the frame crosses the baseline plane at 1.58 em at
// clock 0 and 1.31 em once settled -- so each glyph reads its release height off
// that line at the moment its slot opens. Both figures were bisected by counting
// coral pixels in a rendered frame; re-measure that way if the camera changes.
#declare EdgeNear = 1.58;   // em, top of frame at clock 0
#declare EdgeFar  = 1.31;   // em, top of frame once the camera has settled
#declare Clear    = 0.06;   // margin above the edge

// Note [The fall needs a push]
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
// A pure gravity curve (1 - w^2) leaves rest slowly, so a letter released from
// just out of frame hangs there for several frames before its cap appears. A
// linear term mixed in gives the release a small initial velocity, which brings
// it into shot promptly while keeping the accelerating feel and hard landing.
#declare Push = 0.55;       // 0 = pure gravity, 1 = constant speed

// The bounce is deliberately tiny. A letter that visibly rebounds reads as
// rubber; this is just enough for the contact shadow to detach for a few
// frames, which is what sells the landing.
#declare Bnc  = 0.045;      // fraction of Drop
#declare PhF  = 0.66;       // fraction of a slot spent falling
#declare PhB  = 0.26;       // ... then bouncing; the rest is rest

// Landing slot per glyph. The I is index 2 and takes the last slot.
#declare Slot = array[NC] { 0, 1, 5, 2, 3, 4 }

// ---------------------------------------------------------------------------
// Per glyph, at this clock: On, whether it is in the scene at all, and Dy, its
// vertical offset in em above its final resting place.
// ---------------------------------------------------------------------------
#declare Dy = array[NC];
#declare On = array[NC];

#declare i = 0;
#while (i < NC)
  #declare Col = (Motif = 1 & i = 2);
  #declare Len = (Col ? DurCol : Dur);
  #declare Rel = Slot[i] * Stag;                    // when this glyph is let go
  #declare pu  = (clock - Rel) / Len;

  // ">= 0" and not "> 0": at clock 0 the first glyph is released rather than
  // withheld, which keeps the union from being empty on the opening frame.
  #declare On[i] = (pu >= 0 ? 1 : 0);
  #declare pu    = min(1, max(0, pu));

  // Release height: where the top of the frame is at Rel. Same ease as the
  // camera, evaluated at the release time rather than now.
  #declare rc   = min(1, Rel / CamEase);
  #declare re   = rc * rc * (3 - 2 * rc);
  #declare Drop = EdgeFar + (EdgeNear - EdgeFar) * (1 - re) + Clear;

  #if (pu >= 1)
    #declare Dy[i] = 0;
  #else
    #if (pu < PhF)
      #declare pw    = pu / PhF;
      #declare Dy[i] = Drop * (1 - (Push * pw + (1 - Push) * pw * pw));
    #else
      #if (Col | pu >= PhF + PhB)
        #declare Dy[i] = 0;       // the plinth does not bounce
      #else
        #declare pv    = (pu - PhF) / PhB;
        #declare Dy[i] = Drop * Bnc * 4 * pv * (1 - pv);
      #end
    #end
  #end
  #declare i = i + 1;
#end

// ---------------------------------------------------------------------------
// The word -- same construction as plinth-logo.pov, plus Dy per glyph.
//
// Dy is applied after the texture, so each glyph's vertical colour gradient
// rides along with it and a falling letter looks exactly like a landed one.
// The offsets are inside the union, hence in em: the union carries the scale.
// ---------------------------------------------------------------------------
#declare Word =
union {
  #declare Cur = -TotW / 2;
  #declare i = 0;
  #while (i < NC)
    #if (On[i] = 1)
      #if (Motif = 1 & i = 2)
        object {
          PlinthColumn(ColW, Thick, 1)
          translate x * (Cur + Wid[2] / 2)
          texture { T_Column }
          translate y * Dy[2]
        }
      #else
        object {
          Beveled(Chars[i])
          translate x * (Cur + Wid[i] / 2)
          texture { T_Letter }
          translate y * Dy[i]
        }
      #end
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

// ---------------------------------------------------------------------------
// Note [Camera move]
// ~~~~~~~~~~~~~~~~~~
// A short pull-in: it starts a little further back, a little higher and a
// little wider, and smoothsteps to the still's framing. Small on purpose -- the
// letters are already moving, and a big camera move on top of that makes the
// shot read as busy rather than composed.
//
// The ease is normalised on CamEase rather than on the clock, so the move is
// finished (e = 1 exactly, all three quantities on their final values) before
// the last frames.
// ---------------------------------------------------------------------------
#declare c = min(1, clock / CamEase);
#declare e = c * c * (3 - 2 * c);

camera {
  perspective
  location < 0.0, 6.00 + 1.30 * (1 - e), -29.5 - 3.20 * (1 - e)>
  look_at  < 0.0, 1.15 + 0.22 * (1 - e),   0.0>
  right    x * image_width / image_height
  angle 19 + 2.2 * (1 - e)
}

object { Word }
