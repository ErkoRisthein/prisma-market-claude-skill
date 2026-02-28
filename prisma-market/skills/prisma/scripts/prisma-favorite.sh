#!/usr/bin/env bash
# Manage favorites at Prisma Market (requires authentication)
# Usage:
#   prisma-favorite.sh add <ean>
#   prisma-favorite.sh remove <ean>
#   prisma-favorite.sh list
#
# Token is read from .env file (set via prisma-auth.sh set <token>),
# PRISMA_TOKEN env var, or passed as the last argument.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Source .env if it exists and PRISMA_TOKEN not already set
if [ -z "${PRISMA_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

ACTION="${1:?Usage: prisma-favorite.sh <add|remove|list> [ean]}"

load_token() {
  local explicit="${1:-}"
  if [ -n "$explicit" ]; then
    echo "$explicit"
  elif [ -n "${PRISMA_TOKEN:-}" ]; then
    echo "$PRISMA_TOKEN"
  else
    echo "No token found. Run: prisma-auth.sh set <token>" >&2
    exit 1
  fi
}

API_URL="https://graphql-api.prismamarket.ee"
HEADERS=(
  -H 'Content-Type: application/json'
  -H 'Origin: https://www.prismamarket.ee'
  -H 'Referer: https://www.prismamarket.ee/'
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
)

case "$ACTION" in
  add)
    EAN="${2:?Usage: prisma-favorite.sh add <ean>}"
    TOKEN="$(load_token "${3:-}")"

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'operationName': 'RemoteAddFavorite',
    'variables': {'ean': sys.argv[1]},
    'extensions': {
        'persistedQuery': {
            'version': 1,
            'sha256Hash': '10516e83ccde986e9b5d279e2a3926a99b47f5f5567530da8dfe72d36e23c96f'
        }
    }
}))
" "$EAN")

    RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST "$API_URL" \
      "${HEADERS[@]}" \
      -H "Authorization: Bearer $TOKEN" \
      -d @-)

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors')
if errors:
    print('Error:', errors[0].get('message', json.dumps(errors, ensure_ascii=False)))
    sys.exit(1)

result = data.get('data', {}).get('userFavoritesAddItem')
if result:
    print('Favorite added. Modified at:', result.get('modifiedAt', 'unknown'))
else:
    print('Favorite added.')
" "$RESPONSE"
    ;;

  remove)
    EAN="${2:?Usage: prisma-favorite.sh remove <ean>}"
    TOKEN="$(load_token "${3:-}")"

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'operationName': 'RemoteRemoveFavorite',
    'variables': {'ean': sys.argv[1]},
    'extensions': {
        'persistedQuery': {
            'version': 1,
            'sha256Hash': '53b131facb43a79ef1a1520673322a0674f3022d76d1b9723c804704eab01ea0'
        }
    }
}))
" "$EAN")

    RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST "$API_URL" \
      "${HEADERS[@]}" \
      -H "Authorization: Bearer $TOKEN" \
      -d @-)

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors')
if errors:
    print('Error:', errors[0].get('message', json.dumps(errors, ensure_ascii=False)))
    sys.exit(1)

result = data.get('data', {}).get('userFavoritesRemoveItem')
if result:
    print('Favorite removed. Modified at:', result.get('modifiedAt', 'unknown'))
else:
    print('Favorite removed.')
" "$RESPONSE"
    ;;

  list)
    TOKEN="$(load_token "${2:-}")"

    PARAMS=$(python3 -c "
import json, urllib.parse
extensions = json.dumps({
    'persistedQuery': {
        'version': 1,
        'sha256Hash': '88b4c9acfa611ac2fd9e349a02217d45ce7b4b91cd7c978797a76dad19a66f18'
    }
})
variables = json.dumps({})
print(urllib.parse.urlencode({
    'operationName': 'RemoteUserFavoritesList',
    'variables': variables,
    'extensions': extensions
}))
")

    RESPONSE=$(curl -s -G "$API_URL" \
      --data-raw "$PARAMS" \
      "${HEADERS[@]}" \
      -H "Authorization: Bearer $TOKEN")

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors')
if errors:
    print('Error:', errors[0].get('message', json.dumps(errors, ensure_ascii=False)))
    sys.exit(1)

items = data.get('data', {}).get('userFavorites', {}).get('items', [])
eans = [item['ean'] for item in items]
print(json.dumps(eans, indent=2, ensure_ascii=False))
" "$RESPONSE"
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage: prisma-favorite.sh <add|remove|list> [ean] <token>" >&2
    exit 1
    ;;
esac
