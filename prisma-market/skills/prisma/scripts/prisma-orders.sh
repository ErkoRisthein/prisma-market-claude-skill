#!/usr/bin/env bash
# View order history at Prisma Market (requires authentication)
# Usage:
#   prisma-orders.sh list [limit]        — list recent orders
#   prisma-orders.sh detail <orderId>    — get order details with cart items
#   prisma-orders.sh items <orderId>     — output ean:qty pairs from an order
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

ACTION="${1:?Usage: prisma-orders.sh <list|detail|items> [orderId|limit]}"

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
  list)
    LIMIT="${2:-}"
    TOKEN="$(load_token "${3:-}")"

    PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'query': '''query GetOrderHistoryData(\$domain: Domain) {
  userOrders(domain: \$domain) {
    id
    orderNumber
    orderStatus
    storeName
    totalCost
    deliveryDate
    deliveryMethod
    deliveryTime
  }
}''',
    'variables': {'domain': 'EPRISMA'}
}))
")

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

orders = data.get('data', {}).get('userOrders', [])

limit = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
if limit:
    orders = orders[:int(limit)]

# Compact output: drop null fields
compact = []
for o in orders:
    entry = {k: v for k, v in o.items() if v is not None}
    compact.append(entry)

print(json.dumps(compact, indent=2, ensure_ascii=False))
" "$RESPONSE" "$LIMIT"
    ;;

  detail)
    ORDER_ID="${2:?Usage: prisma-orders.sh detail <orderId>}"
    TOKEN="$(load_token "${3:-}")"

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'query': '''query GetUserOrderById(\$id: ID!) {
  userOrder(id: \$id) {
    id
    createdAt
    storeName
    orderNumber
    orderStatus
    totalCost
    deliveryDate
    deliveryMethod
    cartItems {
      ean
      name
      itemCount
      price
      basicQuantityUnit
    }
  }
}''',
    'variables': {'id': sys.argv[1]}
}))
" "$ORDER_ID")

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

order = data.get('data', {}).get('userOrder')
if not order:
    print('Order not found')
    sys.exit(1)

# Compact cart items
items = order.get('cartItems', [])
compact_items = []
for item in items:
    compact_items.append({
        'ean': item.get('ean'),
        'name': item.get('name'),
        'qty': item.get('itemCount'),
        'price': item.get('price'),
        'unit': item.get('basicQuantityUnit'),
    })

result = {k: v for k, v in order.items() if k != 'cartItems' and v is not None}
result['cartItems'] = compact_items

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE"
    ;;

  items)
    ORDER_ID="${2:?Usage: prisma-orders.sh items <orderId>}"
    TOKEN="$(load_token "${3:-}")"

    PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({
    'query': '''query GetUserOrderById(\$id: ID!) {
  userOrder(id: \$id) {
    cartItems {
      ean
      itemCount
    }
  }
}''',
    'variables': {'id': sys.argv[1]}
}))
" "$ORDER_ID")

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

order = data.get('data', {}).get('userOrder')
if not order:
    print('Order not found')
    sys.exit(1)

for item in order.get('cartItems', []):
    ean = item.get('ean', '')
    qty = item.get('itemCount', 1)
    print('%s:%s' % (ean, qty))
" "$RESPONSE"
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage: prisma-orders.sh <list|detail|items> [orderId|limit]" >&2
    exit 1
    ;;
esac
