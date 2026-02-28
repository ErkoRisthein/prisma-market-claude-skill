#!/usr/bin/env bash
# Get product details by EAN from Prisma Market
# Usage: prisma-product.sh <ean>

set -euo pipefail

EAN="${1:?Usage: prisma-product.sh <ean>}"

QUERY='{ product(id: "'"$EAN"'") { id ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name } ingredientStatement countryName { et } productDetails { nutrients { referenceQuantity nutrients { name value } } } } }'

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

country_name = product.get('countryName') or {}
nutrient_groups = (product.get('productDetails') or {}).get('nutrients') or []
nutrient_block = nutrient_groups[0] if nutrient_groups else {}
nutrient_list = nutrient_block.get('nutrients') or []

comp = product.get('comparisonPrice')
comp_unit = product.get('comparisonUnit')

result = {'name': product['name'], 'ean': product['ean'], 'price': product['price']}
if comp and comp_unit:
    result['comparisonPrice'] = str(comp) + ' €/' + comp_unit
if product.get('brandName'):
    result['brandName'] = product['brandName']
if product.get('frozen'):
    result['frozen'] = True
if product.get('approxPrice'):
    result['approxPrice'] = True
if category:
    result['category'] = category
result['url'] = 'https://www.prismamarket.ee/toode/' + str(product.get('slug','')) + '/' + product['ean']
if country_name.get('et'):
    result['countryOfOrigin'] = country_name['et']
if product.get('ingredientStatement'):
    result['ingredients'] = product['ingredientStatement']
if nutrient_list:
    ref = nutrient_block.get('referenceQuantity')
    nuts = {n['name']: n['value'] for n in nutrient_list}
    result['nutrients'] = ('per ' + ref + ': ' if ref else '') + ', '.join(k + ' ' + v for k, v in nuts.items())

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE"
