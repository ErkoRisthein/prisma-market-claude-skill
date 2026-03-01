#!/usr/bin/env bash
# Search products at Prisma Market
# Usage: prisma-search.sh <term> [limit] [storeId]

set -euo pipefail

source "$(dirname "$0")/_env.sh"

TERM="${1:?Usage: prisma-search.sh <term> [limit] [storeId]}"
LIMIT="${2:-10}"
STORE_ID="${3:-${PRISMA_STORE_ID:-542860184}}"

QUERY='{ store(id: "'"$STORE_ID"'") { products(queryString: "'"$TERM"'", from: 0, limit: '"$LIMIT"', order: desc, orderBy: score) { items { id ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name } ingredientStatement countryName { et } productDetails { nutrients { referenceQuantity nutrients { name value } } } } } } }'

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
    country_name = p.get('countryName') or {}
    nutrient_groups = (p.get('productDetails') or {}).get('nutrients') or []
    nutrient_block = nutrient_groups[0] if nutrient_groups else {}
    nutrient_list = nutrient_block.get('nutrients') or []

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
    if p.get('ingredientStatement'):
        r['ingredients'] = p['ingredientStatement']
    if nutrient_list:
        ref = nutrient_block.get('referenceQuantity')
        nuts = {n['name']: n['value'] for n in nutrient_list}
        r['nutrients'] = ('per ' + ref + ': ' if ref else '') + ', '.join(k + ' ' + v for k, v in nuts.items())
    results.append(r)

print(json.dumps(results, indent=2, ensure_ascii=False))
" "$RESPONSE"
