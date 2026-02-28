#!/usr/bin/env bash
# Get product nutrition details by EAN from Prisma Market
# Usage: prisma-nutrition.sh <ean>

set -euo pipefail

EAN="${1:?Usage: prisma-nutrition.sh <ean>}"

QUERY='{ product(id: "'"$EAN"'") { id ean name price brandName ingredientStatement countryName { et } productDetails { nutrients { referenceQuantity referenceQuantityType nutrients { name value recommendedIntake } } } } }'

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

country_name = product.get('countryName') or {}
nutrient_groups = (product.get('productDetails') or {}).get('nutrients') or []
nutrient_block = nutrient_groups[0] if nutrient_groups else {}
nutrient_list = nutrient_block.get('nutrients') or []
reference = nutrient_block.get('referenceQuantity')

result = {
    'name': product['name'],
    'ean': product['ean'],
    'price': product['price'],
    'brandName': product.get('brandName'),
    'countryOfOrigin': country_name.get('et'),
    'ingredientStatement': product.get('ingredientStatement'),
    'nutrients': {
        'referenceQuantity': reference,
        'values': [
            {'name': n['name'], 'value': n['value'], 'recommendedIntake': n.get('recommendedIntake')}
            for n in nutrient_list
        ]
    } if nutrient_list else None
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE"
