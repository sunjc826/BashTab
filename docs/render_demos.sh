#!/usr/bin/env bash
# Render all BashTab demo tapes and convert them to GIF.
#
# Usage:  docs/render_demos.sh [tape ...]     (default: all docs/demo*.tape)
#
# Requires: vhs (with Wait support), ttyd, ffmpeg, jq, fzf, less, and built Fig specs.
# Tapes Output .mp4 because vhs's built-in GIF encoder produces 0-byte
# files in some containers; ffmpeg does the mp4 -> gif conversion here
# (two-pass palette, 15 fps).
#
# Container note: if chromium fails with a namespace/sandbox error, create
# a wrapper that adds --no-sandbox and put it first on PATH:
#   mkdir -p /tmp/vhs-bin
#   printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox --disable-gpu --disable-dev-shm-usage "$@"\n' > /tmp/vhs-bin/chromium
#   chmod +x /tmp/vhs-bin/chromium
#   PATH=/tmp/vhs-bin:$PATH docs/render_demos.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if (($#)); then
    tapes=("$@")
else
    tapes=(docs/demo*.tape)
fi

for dependency in vhs ttyd ffmpeg jq fzf less; do
    if ! command -v "$dependency" >/dev/null; then
        echo "Missing demo dependency: $dependency" >&2
        exit 1
    fi
done

export BASHTAB_DEMO_OUT_DIR
BASHTAB_DEMO_OUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bashtab-demos.XXXXXX")
trap 'rm -rf "$BASHTAB_DEMO_OUT_DIR"' EXIT

# Validate the entire selection before overwriting any recordings.
for tape in "${tapes[@]}"; do
    [[ -f "$tape" && "$tape" == *.tape ]] || { echo "Not a tape: $tape" >&2; exit 1; }
    vhs validate "$tape"
done

for tape in "${tapes[@]}"; do
    mp4=${tape%.tape}.mp4
    gif=${tape%.tape}.gif
    render_dir=$(mktemp -d "$BASHTAB_DEMO_OUT_DIR/render.XXXXXX")
    echo "== vhs $tape"
    if ! vhs "$tape" --output "$render_dir/clip.mp4"; then
        cat "$BASHTAB_DEMO_OUT_DIR/activation.log" >&2 2>/dev/null || true
        exit 1
    fi
    [[ -s "$render_dir/clip.mp4" ]] || { echo "Empty recording: $mp4" >&2; exit 1; }
    echo "== ffmpeg $mp4 -> $gif"
    ffmpeg -y -v error -i "$render_dir/clip.mp4" \
        -vf "fps=15,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer" \
        "$render_dir/clip.gif"
    [[ -s "$render_dir/clip.gif" ]] || { echo "Empty GIF: $gif" >&2; exit 1; }
    # Replace existing assets only after both new formats have rendered.
    mv "$render_dir/clip.mp4" "$mp4"
    mv "$render_dir/clip.gif" "$gif"
done
