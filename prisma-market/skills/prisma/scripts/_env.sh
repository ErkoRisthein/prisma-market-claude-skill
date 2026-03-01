# Shared env loader for all prisma scripts.
# Checks project root first ($PWD/.env), then falls back to skill-relative path.
# Usage: source "$(dirname "$0")/_env.sh"

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$PWD/.env" ]; then
  ENV_FILE="$PWD/.env"
elif [ -f "$_SCRIPT_DIR/../.env" ]; then
  ENV_FILE="$_SCRIPT_DIR/../.env"
else
  ENV_FILE="$PWD/.env"  # default for writes (prisma-auth.sh set)
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi
