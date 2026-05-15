#!/usr/bin/env bash
# Browse products by Prisma category (slug from prismamarket.ee URL path).
# Usage: prisma-category.sh <slug> [limit] [from] [storeId]
# Examples:
#   prisma-category.sh "lapsed/mahkmed-ja-lapsehooldus" 50
#   prisma-category.sh "lapsed/mahkmed-ja-lapsehooldus/teipmahkmed" 20 0
# The slug is the path after /tooted/ in the URL.
# Reports total available so you know if more pages exist.

set -euo pipefail

source "$(dirname "$0")/_env.sh"

SLUG="${1:?Usage: prisma-category.sh <slug> [limit] [from] [storeId]}"
LIMIT="${2:-50}"
FROM="${3:-0}"
STORE_ID="${4:-${PRISMA_STORE_ID:-542860184}}"

QUERY='{ store(id: "'"$STORE_ID"'") { products(slug: "'"$SLUG"'", queryString: "", from: '"$FROM"', limit: '"$LIMIT"', useRandomId: true) { total from limit items { id ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name } countryName { et } } } } }'

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
errors = data.get('errors')
if errors:
    print(json.dumps({'errors': errors}, indent=2, ensure_ascii=False))
    sys.exit(1)

product_list = data.get('data', {}).get('store', {}).get('products', {}) or {}
products = product_list.get('items', []) if isinstance(product_list, dict) else []
total = product_list.get('total', 0)
returned_from = product_list.get('from', 0)
returned_limit = product_list.get('limit', 0)

if not products:
    print('No products found in this category.')
    sys.exit(0)

results = []
for p in products:
    hierarchy = p.get('hierarchyPath') or []
    category = hierarchy[-1]['name'] if hierarchy else ''
    country_name = p.get('countryName') or {}

    comp = p.get('comparisonPrice')
    comp_unit = p.get('comparisonUnit')

    r = {'name': p['name'], 'ean': p['ean'], 'price': p['price']}
    if comp and comp_unit:
        r['comparisonPrice'] = str(comp) + ' €/' + comp_unit
    if p.get('brandName'):
        r['brandName'] = p['brandName']
    if p.get('frozen'):
        r['frozen'] = True
    if p.get('approxPrice'):
        r['approxPrice'] = True
    if category:
        r['category'] = category
    r['url'] = 'https://www.prismamarket.ee/toode/' + str(p.get('slug','')) + '/' + p['ean']
    if country_name.get('et'):
        r['countryOfOrigin'] = country_name['et']
    results.append(r)

print(json.dumps({
    'total': total,
    'from': returned_from,
    'limit': returned_limit,
    'returned': len(results),
    'items': results,
}, indent=2, ensure_ascii=False))
" "$RESPONSE"
