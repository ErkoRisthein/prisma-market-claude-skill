# Shared env loader for all prisma scripts.
# Sources $PWD/.env if PRISMA_TOKEN (or other PRISMA_* vars) are not already set.
# Usage: source "$(dirname "$0")/_env.sh"

ENV_FILE="$PWD/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi
