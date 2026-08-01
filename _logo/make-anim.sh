#!/usr/bin/env bash
# Render the animated wordmark and assemble it for the site.
#
#   ./make-anim.sh            render 80 frames at 1800x700, encode the clip
#   ./make-anim.sh --draft    quarter size, no antialiasing, ~30s, for timing
#   ./make-anim.sh --encode   re-encode the frames already in frames/, no render
#   ./make-anim.sh --check    verify the tail is still and matches the still PNG
#
# Output: ../assets/images/plinth-wordmark.webm, a VP9 clip that plays once and
# stops on a frame identical to the committed plinth-wordmark.png. See
# Note [The last frame is the still] in plinth-anim.pov for why that matters,
# and index.md for how the two are served together.
set -euo pipefail

cd "$(dirname "$0")"

FRAMES=frames
STILL=../assets/images/plinth-wordmark.png
OUT=../assets/images/plinth-wordmark.webm
MP4=../assets/images/plinth-wordmark.mp4
POSTER=../assets/images/plinth-wordmark-poster.webp
WIDE=1200          # delivered width, same as the still
FPS=30
LAST=80            # keep in step with Final_Frame in anim.ini

# Note [Downsampling does double duty]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Rendering at 1800 and resampling to 1200 sharpens the bevel edges, as it does
# for the still -- but in an animation it also halves the frame-to-frame noise
# from the jittered area lights and the radiosity sampling, which is what would
# otherwise show up as a faint shimmer on the floor. Measured on two frames that
# should be identical: 0.13% mean difference before resampling, well under half
# of that after. Not worth touching the light rig for (and Note [Hitting the
# brand colour] in plinth-common.inc says not to).
mode=${1:-}

case "$mode" in
  --check)
    # 1. Is the tail actually static? Consecutive frames near the end must
    #    differ only by render noise, not by anything still in motion.
    # 2. Does the last frame match the committed still? Same tolerance: both
    #    numbers are the noise floor, so a real mismatch stands out.
    [[ -f $FRAMES/f$LAST.png ]] || { echo "no frames: run ./make-anim.sh first" >&2; exit 1; }
    # The tolerance is the render's own noise floor. Two frames that are meant
    # to be identical still differ by about 0.4%, because the area lights are
    # jittered and the radiosity is sampled afresh each frame; anything actually
    # in motion is far above that. Note the "|| true" on every compare: it exits
    # 1 whenever the images differ at all, which under set -e would abort the
    # check rather than report it.
    tol=0.01
    for pair in "$((LAST - 4)) $((LAST - 2))" "$((LAST - 2)) $LAST"; do
      read -r a b <<<"$pair"
      d=$( { magick compare -metric RMSE "$FRAMES/f$a.png" "$FRAMES/f$b.png" null: 2>&1 || true; } |
            sed 's/.*(\(.*\))/\1/')
      echo "frame $a vs $b: $d"
      awk -v d="$d" -v t="$tol" 'BEGIN { exit !(d > t) }' &&
        { echo "  FAIL: still moving at frame $b" >&2; exit 1; }
    done
    # -resize before both filenames applies to both as they are read, so this
    # compares the 1800-wide frame against the 1200-wide still on equal terms.
    d=$( { magick compare -metric RMSE -resize ${WIDE}x "$FRAMES/f$LAST.png" "$STILL" null: 2>&1 || true; } |
          sed 's/.*(\(.*\))/\1/')
    echo "frame $LAST vs $(basename $STILL): $d"
    awk -v d="$d" -v t="$tol" 'BEGIN { exit !(d > t) }' &&
      { echo "  FAIL: last frame is not the committed still" >&2; exit 1; }
    echo "ok"
    exit 0
    ;;
  --draft)
    render=(povray anim.ini +W450 +H175 -A +Q5)
    OUT=draft.webm
    WIDE=450
    ;;
  --encode)
    # Retuning the encoder is the thing you do repeatedly; re-rendering 80
    # frames to do it is five minutes for nothing.
    [[ -f $FRAMES/f$LAST.png ]] || { echo "no frames: run ./make-anim.sh first" >&2; exit 1; }
    render=(true)
    ;;
  "")
    render=(povray anim.ini)
    ;;
  *)
    sed -n '2,9p' "$0" >&2
    exit 1
    ;;
esac

if [[ $mode != --encode ]]; then
  mkdir -p "$FRAMES"
  rm -f "$FRAMES"/f*.png
fi
"${render[@]}"

# Note [VP9, not animated WebP]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This clip is 90% smooth near-white backdrop, which is the worst case for
# WebP: it lays visible horizontal streaks across the gradient, and the quality
# knob does not buy them off. Measured on the backdrop alone, against the
# unencoded frame -- q88 0.0080, q99 0.0076, for 848K and 2.2M respectively.
# VP9 reaches the same number at crf 20 in 200K and is visibly cleaner by
# crf 16, because it has a deblocking filter and rate control built for exactly
# this. Lossless WebP would do it in 12M.
#
# Odd heights are fine for VP9, so the frame is 1200x467 -- the same size as
# the still, which is the poster.
#
# No -loop: a <video> stops on its last frame, which is the whole design (see
# Note [The last frame is the still] in plinth-anim.pov). That frame is then on
# screen indefinitely, so -force_key_frames codes it as a keyframe rather than
# the tail of a 79-frame delta chain. Costs about 20K.
ffmpeg -nostdin -loglevel error -y \
  -framerate "$FPS" -start_number 1 -i "$FRAMES/f%02d.png" \
  -vf "scale=$WIDE:-1:flags=lanczos" \
  -c:v libvpx-vp9 -crf 16 -b:v 0 -pix_fmt yuv420p \
  -force_key_frames "expr:eq(n,$((LAST - 1)))" \
  -deadline good -cpu-used 1 -row-mt 1 -an \
  "$OUT"

printf '%s  %s  %s frames @ %sfps\n' \
  "$OUT" "$(du -h "$OUT" | cut -f1)" "$LAST" "$FPS"

if [[ $mode == --draft ]]; then
  exit 0
fi

# Note [The poster is the FIRST frame]
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Not the last one, which is the obvious choice and is wrong: the poster is what
# the browser shows until playback starts, so posting the finished wordmark
# means arriving on the page, seeing the completed mark, and then watching it
# vanish and rebuild itself. Frame 1 makes the handover invisible.
#
# The cost is that a browser that cannot play either source is left on an empty
# studio, which is why the H.264 fallback below exists -- with it, "no playable
# source" stops being a case that happens. Cheap at 4K: frame 1 is nearly flat,
# and the streaking that ruled WebP out for the animation (see Note [VP9, not
# animated WebP]) does not arise on one still image at this bitrate.
ffmpeg -nostdin -loglevel error -y -i "$FRAMES/f01.png" \
  -vf "scale=$WIDE:-1:flags=lanczos" \
  -c:v libwebp -lossless 0 -quality 90 -compression_level 6 \
  "$POSTER"

# H.264 for anything too old for VP9 -- pre-2021 Safari, mainly. Modern browsers
# take the WebM listed first in index.md and never fetch this. 466 not 467:
# H.264 requires even dimensions, and one pixel of letterbox is not visible.
ffmpeg -nostdin -loglevel error -y \
  -framerate "$FPS" -start_number 1 -i "$FRAMES/f%02d.png" \
  -vf "scale=$WIDE:466:flags=lanczos" \
  -c:v libx264 -crf 19 -preset slow -pix_fmt yuv420p \
  -movflags +faststart -an \
  "$MP4"

printf '%s  %s\n%s  %s\n' \
  "$POSTER" "$(du -h "$POSTER" | cut -f1)" \
  "$MP4"    "$(du -h "$MP4" | cut -f1)"
