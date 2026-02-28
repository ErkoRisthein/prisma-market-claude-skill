#!/usr/bin/env bash
# Search products at Prisma Market
# Usage: prisma-search.sh <term> [limit] [storeId]

set -euo pipefail

TERM="${1:?Usage: prisma-search.sh <term> [limit] [storeId]}"
LIMIT="${2:-10}"
STORE_ID="${3:-542860184}"

QUERY='{ store(id: "'"$STORE_ID"'") { products(queryString: "'"$TERM"'", from: 0, limit: '"$LIMIT"', order: desc, orderBy: score) { items { id ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name } } } } }'

PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$QUERY")

RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST https://graphql-api.prismamarket.ee \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://www.prismamarket.ee' \
  -H 'Referer: https://www.prismamarket.ee/' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
  -d @-)

python3 -c "
import json, sys

data = json.loads(sys.argv[1])
product_list = data.get('data', {}).get('store', {}).get('products', {})
products = product_list.get('items', []) if isinstance(product_list, dict) else []

if not products:
    print('No products found.')
    sys.exit(0)

results = []
for p in products:
    hierarchy = p.get('hierarchyPath') or []
    category = hierarchy[0]['name'] if hierarchy else ''
    results.append({
        'name': p['name'],
        'ean': p['ean'],
        'price': p['price'],
        'comparisonPrice': p.get('comparisonPrice'),
        'comparisonUnit': p.get('comparisonUnit'),
        'brandName': p.get('brandName'),
        'slug': p.get('slug'),
        'frozen': p.get('frozen', False),
        'approxPrice': p.get('approxPrice', False),
        'mainCategoryName': category,
        'url': 'https://www.prismamarket.ee/toode/' + str(p.get('slug','')) + '/' + p['ean']
    })

print(json.dumps(results, indent=2, ensure_ascii=False))
" "$RESPONSE"
