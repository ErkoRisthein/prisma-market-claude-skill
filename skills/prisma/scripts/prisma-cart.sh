#!/usr/bin/env bash
# Populate Prisma Market browser cart
# Usage:
#   prisma-cart.sh populate [storeId] <ean1:qty1> [ean2:qty2] ...
#
# Fetches product details, validates availability, and outputs Playwright code
# for browser_run_code that populates the cart via localStorage and opens /kokkuvote.
#
# Default store: 542860184 (Kristiine Prisma)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

ACTION="${1:?Usage: prisma-cart.sh populate [storeId] <ean1:qty1> ...}"
shift

# Check if first arg looks like a store ID (all digits) or an ean:qty pair
if [[ "${1:-}" =~ ^[0-9]+$ ]] && [[ ! "${1:-}" =~ : ]]; then
  STORE_ID="$1"
  shift
else
  STORE_ID="${PRISMA_STORE_ID:-542860184}"
fi

if [ $# -eq 0 ]; then
  echo "Error: At least one ean:quantity pair required" >&2
  exit 1
fi

API_URL="https://graphql-api.prismamarket.ee"
CURL_HEADERS=(
  -H 'Content-Type: application/json'
  -H 'Origin: https://www.prismamarket.ee'
  -H 'Referer: https://www.prismamarket.ee/'
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
)

case "$ACTION" in
  populate)
    # Step 1: Fetch product details for all EANs and generate Playwright code
    PLAYWRIGHT_CODE=$(python3 -c "
import json, sys, subprocess

store_id = sys.argv[1]
api_url = sys.argv[2]
items_raw = sys.argv[3:]

# Parse ean:qty pairs
cart_items = []
for arg in items_raw:
    parts = arg.split(':')
    if len(parts) != 2:
        print(f'Error: Invalid format \"{arg}\". Use ean:quantity', file=sys.stderr)
        sys.exit(1)
    cart_items.append({'ean': parts[0], 'qty': int(parts[1])})

eans = [item['ean'] for item in cart_items]
qty_map = {item['ean']: item['qty'] for item in cart_items}

# Build aliased GraphQL query for all products
fields = 'ean name price comparisonPrice comparisonUnit brandName slug frozen approxPrice hierarchyPath { name }'
aliases = ' '.join(
    f'p{i}: product(id: \"{ean}\") {{ {fields} }}'
    for i, ean in enumerate(eans)
)
query = '{ ' + aliases + ' }'

payload = json.dumps({'query': query})
result = subprocess.run(
    ['curl', '-s', '-X', 'POST', api_url,
     '-H', 'Content-Type: application/json',
     '-H', 'Origin: https://www.prismamarket.ee',
     '-H', 'Referer: https://www.prismamarket.ee/',
     '-H', 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
     '-d', payload],
    capture_output=True, text=True
)
data = json.loads(result.stdout).get('data', {})

# Build ClientCartItem objects
js_items = []
missing = []
for i, ean in enumerate(eans):
    product = data.get(f'p{i}')
    if not product:
        missing.append(ean)
        continue

    hierarchy = product.get('hierarchyPath') or []
    category = hierarchy[0]['name'] if hierarchy else ''

    item = {
        '__typename': 'ClientCartItem',
        'id': ean,
        'ean': ean,
        'name': product['name'],
        'price': product['price'],
        'regularPrice': product['price'],
        'comparisonPrice': product.get('comparisonPrice'),
        'comparisonUnit': product.get('comparisonUnit'),
        'frozen': product.get('frozen', False),
        'approxPrice': product.get('approxPrice', False),
        'mainCategoryName': category,
        'itemCount': qty_map[ean],
        'basicQuantityUnit': 'KPL',
        'inStoreSelection': True,
        'priceUnit': 'KPL',
        'quantityMultiplier': 1,
        'replace': True,
        'countryName': {'et': None, '__typename': 'CountryName'},
        'productType': 'PRODUCT',
        'campaignPrice': None,
        'lowest30DayPrice': None,
        'campaignPriceValidUntil': None,
        'additionalInfo': '',
        'isAgeLimitedByAlcohol': False,
        'packagingLabelCodes': [],
        'isForceSalesByCount': False,
    }
    js_items.append(item)

if missing:
    print(f'Error: Products not found: {missing}', file=sys.stderr)
    sys.exit(1)

# Print summary to stderr
total = sum(item['price'] * item['itemCount'] for item in js_items)
print(f'Cart: {len(js_items)} items, estimated total: {total:.2f} €', file=sys.stderr)
for item in js_items:
    print(f'  {item[\"ean\"]} {item[\"name\"]} x{item[\"itemCount\"]} = {item[\"price\"] * item[\"itemCount\"]:.2f} €', file=sys.stderr)

# Generate Playwright code
cart_data = {
    'cacheVersion': '1.2.17',
    'cart': {'cartItems': js_items},
    'orderEditActive': None,
}
cart_json = json.dumps(cart_data, ensure_ascii=False)

print(f'''async (page) => {{
  await page.goto('https://www.prismamarket.ee');
  await page.waitForLoadState('networkidle');

  const result = await page.evaluate((cartJson) => {{
    // Bypass cookie consent
    const raw = localStorage.getItem('uc_settings');
    if (raw) {{
      const settings = JSON.parse(raw);
      const now = Date.now();
      for (const service of settings.services) {{
        const hasAccepted = service.history.some(h => h.action === 'onAcceptAllServices');
        if (!hasAccepted) {{
          service.history.push({{
            action: 'onAcceptAllServices',
            language: 'et',
            status: true,
            timestamp: now,
            type: 'explicit',
            versions: service.history[0].versions
          }});
        }}
      }}
      localStorage.setItem('uc_settings', JSON.stringify(settings));
      localStorage.setItem('uc_user_interaction', 'true');
    }}

    // Write cart data
    localStorage.setItem('cart-data', cartJson);
    const written = JSON.parse(localStorage.getItem('cart-data'));
    return {{ success: true, itemCount: written.cart.cartItems.length }};
  }}, {json.dumps(cart_json)});

  // Navigate to cart summary
  await page.goto('https://www.prismamarket.ee/kokkuvote');
  await page.waitForLoadState('networkidle');

  return result;
}};''')
" "$STORE_ID" "$API_URL" "$@")

    echo "$PLAYWRIGHT_CODE"
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage: prisma-cart.sh populate [storeId] <ean1:qty1> ..." >&2
    exit 1
    ;;
esac
