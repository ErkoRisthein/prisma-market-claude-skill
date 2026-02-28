#!/usr/bin/env bash
# Validate cart items at Prisma Market (check availability + prices)
# Usage: prisma-validate-cart.sh <storeId> <ean1:qty1> [ean2:qty2] ...

set -euo pipefail

STORE_ID="${1:?Usage: prisma-validate-cart.sh <storeId> <ean1:qty1> [ean2:qty2] ...}"
shift

if [ $# -eq 0 ]; then
  echo "Error: At least one ean:quantity pair required" >&2
  exit 1
fi

# Build the payload using python3 to handle JSON escaping properly
PAYLOAD=$(python3 -c "
import json, sys

store_id = sys.argv[1]
items = []
for arg in sys.argv[2:]:
    parts = arg.split(':')
    if len(parts) != 2:
        print(f'Error: Invalid format \"{arg}\". Use ean:quantity', file=sys.stderr)
        sys.exit(1)
    items.append({'ean': parts[0], 'itemCount': parts[1]})

query = 'query ValidateCart(\$storeId: ID!, \$items: [PartialCartItemInput!]!) { validateCart(storeId: \$storeId, partialCartItems: \$items) { isOrderingPossible cartValidationItems { ean availableQuantity product { name price pricing { campaignPrice regularPrice currentPrice } } } } }'

print(json.dumps({
    'query': query,
    'variables': {
        'storeId': store_id,
        'items': items
    }
}))
" "$STORE_ID" "$@")

RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST https://graphql-api.prismamarket.ee \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://www.prismamarket.ee' \
  -H 'Referer: https://www.prismamarket.ee/' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
  -d @-)

python3 -c "
import json, sys

data = json.loads(sys.argv[1])
items_raw = sys.argv[2:]

# Parse input items for quantity lookup
qty_map = {}
for arg in items_raw:
    parts = arg.split(':')
    qty_map[parts[0]] = int(parts[1])

validation = data.get('data', {}).get('validateCart')

if not validation:
    errors = data.get('errors', [])
    if errors:
        print('API errors:')
        for e in errors:
            print('  - ' + e.get('message', str(e)))
    else:
        print('No validation data returned.')
        print('Response: ' + json.dumps(data, indent=2))
    sys.exit(1)

result = {
    'isOrderingPossible': validation['isOrderingPossible'],
    'items': []
}

total = 0.0
for item in validation.get('cartValidationItems', []):
    product = item.get('product') or {}
    pricing = product.get('pricing') or {}
    qty = qty_map.get(item['ean'], 1)
    price = pricing.get('currentPrice') or product.get('price', 0)
    line_total = price * qty

    result['items'].append({
        'ean': item['ean'],
        'name': product.get('name', ''),
        'price': price,
        'regularPrice': pricing.get('regularPrice'),
        'campaignPrice': pricing.get('campaignPrice'),
        'availableQuantity': item.get('availableQuantity'),
        'requestedQuantity': qty,
        'lineTotal': round(line_total, 2)
    })
    total += line_total

result['estimatedTotal'] = round(total, 2)

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE" "$@"
