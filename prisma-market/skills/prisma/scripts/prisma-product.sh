#!/usr/bin/env bash
# Get product details by EAN from Prisma Market
# Usage: prisma-product.sh <ean>

set -euo pipefail

EAN="${1:?Usage: prisma-product.sh <ean>}"

QUERY='{ product(id: "'"$EAN"'") { id ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name } } }'

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
product = data.get('data', {}).get('product')

if not product:
    print('Product not found.')
    sys.exit(1)

hierarchy = product.get('hierarchyPath') or []
category = hierarchy[0]['name'] if hierarchy else ''

result = {
    'name': product['name'],
    'ean': product['ean'],
    'price': product['price'],
    'comparisonPrice': product.get('comparisonPrice'),
    'comparisonUnit': product.get('comparisonUnit'),
    'brandName': product.get('brandName'),
    'slug': product.get('slug'),
    'frozen': product.get('frozen', False),
    'approxPrice': product.get('approxPrice', False),
    'mainCategoryName': category,
    'url': 'https://www.prismamarket.ee/toode/' + str(product.get('slug','')) + '/' + product['ean']
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE"
