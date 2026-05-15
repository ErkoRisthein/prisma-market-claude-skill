#!/usr/bin/env bash
# Fetch product image(s) from Prisma's CDN and save as PNG(s) for inspection.
# Useful for verifying packaging type (pouch vs jar), checking product appearance, etc.
#
# Usage: prisma-image.sh <ean1> [ean2] [ean3] ...
# Output: prints absolute path(s) to downloaded PNG file(s), one per line
#
# Example:
#   prisma-image.sh 4740073076217
#   # -> /tmp/prisma_images/4740073076217.png
#
# Requires: curl, dwebp (from `brew install webp`)

set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 <ean1> [ean2] ..." >&2
  echo "Downloads product image(s) from Prisma CDN as PNG to /tmp/prisma_images/" >&2
  exit 1
fi

if ! command -v dwebp >/dev/null 2>&1; then
  echo "Error: dwebp not found. Install with: brew install webp" >&2
  exit 1
fi

OUT_DIR="/tmp/prisma_images"
mkdir -p "$OUT_DIR"

for EAN in "$@"; do
  if [[ ! "$EAN" =~ ^[0-9]+$ ]]; then
    echo "Warning: skipping non-numeric arg: $EAN" >&2
    continue
  fi

  WEBP_PATH="$OUT_DIR/${EAN}.webp"
  PNG_PATH="$OUT_DIR/${EAN}.png"
  URL="https://cdn.s-cloud.fi/v1/w720h720@_q75/product/ean/${EAN}_kuva1.webp"

  if ! curl -sf -o "$WEBP_PATH" "$URL"; then
    echo "Error: failed to fetch $URL" >&2
    continue
  fi

  if ! dwebp "$WEBP_PATH" -o "$PNG_PATH" >/dev/null 2>&1; then
    echo "Error: failed to convert $WEBP_PATH" >&2
    continue
  fi

  rm -f "$WEBP_PATH"
  echo "$PNG_PATH"
done
