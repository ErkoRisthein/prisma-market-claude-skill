#!/usr/bin/env bash
# Edit a placed Prisma Market order via the UpdateOrder mutation
# Usage:
#   prisma-edit-order.sh show <orderId>                        — show current order items
#   prisma-edit-order.sh add <orderId> <ean:qty> [ean:qty...]  — add items (or increase qty)
#   prisma-edit-order.sh remove <orderId> <ean> [ean...]       — remove items
#   prisma-edit-order.sh set <orderId> <ean:qty> [ean:qty...]  — set exact quantities (0 = remove)
#   prisma-edit-order.sh replace <orderId> <ean:qty> [ean:qty...]  — replace entire cart
#   prisma-edit-order.sh slot <orderId> <newSlotId>            — change delivery slot
#                                                                (reserves new slot, then UpdateOrder)
#
# Reads from .env:
#   PRISMA_TOKEN — JWT auth token (required)
#   PRISMA_STORE_ID — store ID (default: 542860184)

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/_env.sh"

API="https://graphql-api.prismamarket.ee"
STORE_ID="${PRISMA_STORE_ID:-542860184}"
PACKAGING_EAN="6438460490682"

# Common headers
curl_common() {
  curl -s "$@" \
    -H 'Origin: https://www.prismamarket.ee' \
    -H 'Referer: https://www.prismamarket.ee/' \
    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

# Common headers + auth
curl_auth() {
  local token="${PRISMA_TOKEN:?Set PRISMA_TOKEN in .env (use prisma-auth.sh login)}"
  curl_common "$@" \
    -H "Authorization: Bearer $token"
}

# Fetch order by ID — returns full order JSON with cart items, customer, deliverySlotId
fetch_order() {
  local order_id="$1"

  local payload
  payload=$(python3 -c "
import json, sys
print(json.dumps({
    'operationName': 'GetOrderById',
    'query': '''query GetOrderById(\$id: ID!) {
  order(id: \$id) {
    id
    orderNumber
    orderStatus
    deliveryDate
    deliveryTime
    deliverySlotId
    storeId
    additionalInfo
    customer {
      companyName
      companyIdentityCode
      firstName
      lastName
      phone
      email
      invoiceNumber
      addressLine1
      addressLine2
      city
      postalCode
      geocodedAddress {
        position { lat lng }
      }
    }
    cartItems {
      ean
      name
      itemCount
      price
      basicQuantityUnit
      additionalInfo
      replace
      priceUnit
      productType
    }
  }
}''',
    'variables': {'id': sys.argv[1]}
}))
" "$order_id")

  printf '%s' "$payload" | curl_auth -X POST "$API" \
    -H 'Content-Type: application/json' \
    -d @-
}

# Send UpdateOrder mutation. Sends the full GraphQL query text rather than
# relying on Apollo Automatic Persisted Queries (the hash gets rotated by
# Prisma occasionally and silently breaks edits). The query lives next to
# this script — re-capture it via Playwright if the server schema changes.
send_update() {
  local order_id="$1"
  local variables_json="$2"

  local query_file="$_SCRIPT_DIR/update-order.graphql"
  if [ ! -f "$query_file" ]; then
    echo "Error: $query_file not found. Re-capture from a live Prisma UpdateOrder request." >&2
    return 1
  fi

  local payload
  payload=$(python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    query = f.read()
variables = json.loads(sys.argv[2])
print(json.dumps({
    'operationName': 'UpdateOrder',
    'query': query,
    'variables': variables
}))
" "$query_file" "$variables_json")

  printf '%s' "$payload" | curl_auth -X POST "$API" \
    -H 'Content-Type: application/json' \
    -d @-
}

# Parse fetch_order response, validate, return order data as JSON
parse_order() {
  local response="$1"
  python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        msg = e.get('message', str(e))
        print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)

order = data.get('data', {}).get('order')
if not order:
    print('Order not found', file=sys.stderr)
    sys.exit(1)

print(json.dumps(order, ensure_ascii=False))
" "$response"
}

# Parse UpdateOrder response
parse_update_response() {
  local response="$1"
  python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        msg = e.get('message', str(e))
        ext = e.get('extensions', {})
        code = ext.get('code', '')
        print(f'ERROR [{code}]: {msg}', file=sys.stderr)
        for ve in ext.get('validationErrors', []):
            print(f'  - {ve.get(\"path\", [])}: {ve.get(\"message\", \"\")}', file=sys.stderr)
    sys.exit(1)

result = data.get('data', {}).get('updateOrder')
if not result:
    print('No update response data returned', file=sys.stderr)
    print(json.dumps(data, indent=2), file=sys.stderr)
    sys.exit(1)

# Clean output
clean = {k: v for k, v in result.items() if v is not None and k != '__typename'}
if 'cartItems' in clean:
    clean['cartItems'] = [{k: v for k, v in item.items() if v is not None and k != '__typename'} for item in clean['cartItems']]
if 'customer' in clean:
    clean['customer'] = {k: v for k, v in clean['customer'].items() if v is not None and k != '__typename'}

print(json.dumps(clean, indent=2, ensure_ascii=False))
" "$response"
}

ACTION="${1:?Usage: prisma-edit-order.sh [show|add|remove|set|replace|slot] <orderId> ...}"
shift

case "$ACTION" in

  # ---- SHOW ------------------------------------------------
  # Show current order items
  # Usage: prisma-edit-order.sh show <orderId>
  show)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh show <orderId>}"

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    python3 -c "
import json, sys

order = json.loads(sys.argv[1])
items = order.get('cartItems', [])

compact_items = []
for item in items:
    compact_items.append({
        'ean': item.get('ean'),
        'name': item.get('name'),
        'qty': item.get('itemCount'),
        'price': item.get('price'),
        'unit': item.get('basicQuantityUnit'),
        'priceUnit': item.get('priceUnit'),
    })

result = {
    'orderId': order.get('id'),
    'orderNumber': order.get('orderNumber'),
    'orderStatus': order.get('orderStatus'),
    'totalCost': order.get('totalCost'),
    'deliveryDate': order.get('deliveryDate'),
    'deliveryTime': order.get('deliveryTime'),
    'itemCount': len([i for i in items if i.get('ean') != '6438460490682']),
    'cartItems': compact_items,
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$ORDER_JSON"
    ;;

  # ---- ADD --------------------------------------------------
  # Add items to the order (or increase qty if already present)
  # Usage: prisma-edit-order.sh add <orderId> <ean:qty> [ean:qty...]
  add)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh add <orderId> <ean:qty> [ean:qty...]}"
    shift
    if [ $# -eq 0 ]; then
      echo "Error: At least one ean:qty pair required" >&2
      exit 1
    fi

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    echo "Adding $# item(s) to order..." >&2

    VARS=$(python3 -c "
import json, sys

order = json.loads(sys.argv[1])
order_id = sys.argv[2]
packaging_ean = sys.argv[3]
new_pairs = sys.argv[4:]

# Parse new ean:qty[:r] pairs
additions = {}
for pair in new_pairs:
    parts = pair.split(':')
    if len(parts) not in (2, 3):
        print(f'Error: Invalid format \"{pair}\". Use ean:quantity or ean:quantity:r', file=sys.stderr)
        sys.exit(1)
    allow_replace = len(parts) == 3 and parts[2] == 'r'
    additions[parts[0]] = (int(parts[1]), allow_replace)

# Build cart items from existing order
existing = {}
for item in order.get('cartItems', []):
    ean = item['ean']
    if ean == packaging_ean or item.get('productType') != 'PRODUCT':
        continue
    existing[ean] = {
        'additionalInfo': item.get('additionalInfo', ''),
        'basicQuantityUnit': item.get('basicQuantityUnit', 'KPL'),
        'ean': ean,
        'itemCount': str(item.get('itemCount', 1)),
        'replace': item.get('replace', False),
    }

# Add or increase quantities
for ean, (qty, allow_replace) in additions.items():
    if ean in existing:
        current = int(existing[ean]['itemCount'])
        existing[ean]['itemCount'] = str(current + qty)
        if allow_replace:
            existing[ean]['replace'] = True
    else:
        existing[ean] = {
            'additionalInfo': '',
            'basicQuantityUnit': 'KPL',
            'ean': ean,
            'itemCount': str(qty),
            'replace': allow_replace,
        }

cart_items = list(existing.values())

# Append packaging item
cart_items.append({
    'additionalInfo': '',
    'basicQuantityUnit': 'KPL',
    'ean': packaging_ean,
    'itemCount': '1',
    'replace': False,
})

# Build customer from fetched order
customer = order.get('customer', {})
geo = customer.get('geocodedAddress', {})
pos = geo.get('position', {}) if geo else {}
customer_input = {
    'companyName': customer.get('companyName'),
    'companyIdentityCode': customer.get('companyIdentityCode'),
    'email': customer.get('email', ''),
    'firstName': customer.get('firstName', ''),
    'lastName': customer.get('lastName', ''),
    'phone': customer.get('phone', ''),
    'invoiceNumber': customer.get('invoiceNumber', ''),
    'addressLine1': customer.get('addressLine1', ''),
    'addressLine2': customer.get('addressLine2'),
    'city': customer.get('city', 'Tallinn'),
    'postalCode': customer.get('postalCode', ''),
}
if pos:
    customer_input['addressCoordinates'] = {
        'latitude': pos.get('lat'),
        'longitude': pos.get('lng'),
    }

variables = {
    'id': order_id,
    'order': {
        'cartItems': cart_items,
        'customer': customer_input,
        'paymentMethod': 'CARD_PAYMENT',
        'storeId': order.get('storeId', ''),
        'reservationId': None,
        'deliverySlotId': order.get('deliverySlotId', ''),
        'discountCode': '',
        'additionalInfo': order.get('additionalInfo', ''),
    }
}

print(json.dumps(variables, ensure_ascii=False))
" "$ORDER_JSON" "$ORDER_ID" "$PACKAGING_EAN" "$@")

    RESPONSE=$(send_update "$ORDER_ID" "$VARS")
    parse_update_response "$RESPONSE"
    ;;

  # ---- REMOVE -----------------------------------------------
  # Remove items from the order
  # Usage: prisma-edit-order.sh remove <orderId> <ean> [ean...]
  remove)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh remove <orderId> <ean> [ean...]}"
    shift
    if [ $# -eq 0 ]; then
      echo "Error: At least one EAN required" >&2
      exit 1
    fi

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    echo "Removing $# item(s) from order..." >&2

    VARS=$(python3 -c "
import json, sys

order = json.loads(sys.argv[1])
order_id = sys.argv[2]
packaging_ean = sys.argv[3]
remove_eans = set(sys.argv[4:])

# Build cart items, skipping removed EANs and packaging
cart_items = []
removed = set()
for item in order.get('cartItems', []):
    ean = item['ean']
    if ean == packaging_ean or item.get('productType') != 'PRODUCT':
        continue
    if ean in remove_eans:
        removed.add(ean)
        continue
    cart_items.append({
        'additionalInfo': item.get('additionalInfo', ''),
        'basicQuantityUnit': item.get('basicQuantityUnit', 'KPL'),
        'ean': ean,
        'itemCount': str(item.get('itemCount', 1)),
        'replace': item.get('replace', False),
    })

not_found = remove_eans - removed
if not_found:
    print(f'Warning: EANs not found in order: {not_found}', file=sys.stderr)

# Append packaging item
cart_items.append({
    'additionalInfo': '',
    'basicQuantityUnit': 'KPL',
    'ean': packaging_ean,
    'itemCount': '1',
    'replace': False,
})

# Build customer from fetched order
customer = order.get('customer', {})
geo = customer.get('geocodedAddress', {})
pos = geo.get('position', {}) if geo else {}
customer_input = {
    'companyName': customer.get('companyName'),
    'companyIdentityCode': customer.get('companyIdentityCode'),
    'email': customer.get('email', ''),
    'firstName': customer.get('firstName', ''),
    'lastName': customer.get('lastName', ''),
    'phone': customer.get('phone', ''),
    'invoiceNumber': customer.get('invoiceNumber', ''),
    'addressLine1': customer.get('addressLine1', ''),
    'addressLine2': customer.get('addressLine2'),
    'city': customer.get('city', 'Tallinn'),
    'postalCode': customer.get('postalCode', ''),
}
if pos:
    customer_input['addressCoordinates'] = {
        'latitude': pos.get('lat'),
        'longitude': pos.get('lng'),
    }

variables = {
    'id': order_id,
    'order': {
        'cartItems': cart_items,
        'customer': customer_input,
        'paymentMethod': 'CARD_PAYMENT',
        'storeId': order.get('storeId', ''),
        'reservationId': None,
        'deliverySlotId': order.get('deliverySlotId', ''),
        'discountCode': '',
        'additionalInfo': order.get('additionalInfo', ''),
    }
}

print(json.dumps(variables, ensure_ascii=False))
" "$ORDER_JSON" "$ORDER_ID" "$PACKAGING_EAN" "$@")

    RESPONSE=$(send_update "$ORDER_ID" "$VARS")
    parse_update_response "$RESPONSE"
    ;;

  # ---- SET --------------------------------------------------
  # Set exact quantities (0 = remove)
  # Usage: prisma-edit-order.sh set <orderId> <ean:qty> [ean:qty...]
  set)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh set <orderId> <ean:qty> [ean:qty...]}"
    shift
    if [ $# -eq 0 ]; then
      echo "Error: At least one ean:qty pair required" >&2
      exit 1
    fi

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    echo "Setting quantities for $# item(s)..." >&2

    VARS=$(python3 -c "
import json, sys

order = json.loads(sys.argv[1])
order_id = sys.argv[2]
packaging_ean = sys.argv[3]
set_pairs = sys.argv[4:]

# Parse ean:qty[:r] pairs
updates = {}
for pair in set_pairs:
    parts = pair.split(':')
    if len(parts) not in (2, 3):
        print(f'Error: Invalid format \"{pair}\". Use ean:quantity or ean:quantity:r', file=sys.stderr)
        sys.exit(1)
    allow_replace = len(parts) == 3 and parts[2] == 'r'
    updates[parts[0]] = (int(parts[1]), allow_replace)

# Build cart items from existing order, applying updates
cart_items = []
updated = set()
for item in order.get('cartItems', []):
    ean = item['ean']
    if ean == packaging_ean or item.get('productType') != 'PRODUCT':
        continue
    if ean in updates:
        updated.add(ean)
        qty, allow_replace = updates[ean]
        if qty <= 0:
            continue  # qty 0 = remove
        cart_items.append({
            'additionalInfo': item.get('additionalInfo', ''),
            'basicQuantityUnit': item.get('basicQuantityUnit', 'KPL'),
            'ean': ean,
            'itemCount': str(qty),
            'replace': allow_replace,
        })
    else:
        cart_items.append({
            'additionalInfo': item.get('additionalInfo', ''),
            'basicQuantityUnit': item.get('basicQuantityUnit', 'KPL'),
            'ean': ean,
            'itemCount': str(item.get('itemCount', 1)),
            'replace': item.get('replace', False),
        })

# Add new items that weren't in the original order
for ean, (qty, allow_replace) in updates.items():
    if ean not in updated and qty > 0:
        cart_items.append({
            'additionalInfo': '',
            'basicQuantityUnit': 'KPL',
            'ean': ean,
            'itemCount': str(qty),
            'replace': allow_replace,
        })

# Append packaging item
cart_items.append({
    'additionalInfo': '',
    'basicQuantityUnit': 'KPL',
    'ean': packaging_ean,
    'itemCount': '1',
    'replace': False,
})

# Build customer from fetched order
customer = order.get('customer', {})
geo = customer.get('geocodedAddress', {})
pos = geo.get('position', {}) if geo else {}
customer_input = {
    'companyName': customer.get('companyName'),
    'companyIdentityCode': customer.get('companyIdentityCode'),
    'email': customer.get('email', ''),
    'firstName': customer.get('firstName', ''),
    'lastName': customer.get('lastName', ''),
    'phone': customer.get('phone', ''),
    'invoiceNumber': customer.get('invoiceNumber', ''),
    'addressLine1': customer.get('addressLine1', ''),
    'addressLine2': customer.get('addressLine2'),
    'city': customer.get('city', 'Tallinn'),
    'postalCode': customer.get('postalCode', ''),
}
if pos:
    customer_input['addressCoordinates'] = {
        'latitude': pos.get('lat'),
        'longitude': pos.get('lng'),
    }

variables = {
    'id': order_id,
    'order': {
        'cartItems': cart_items,
        'customer': customer_input,
        'paymentMethod': 'CARD_PAYMENT',
        'storeId': order.get('storeId', ''),
        'reservationId': None,
        'deliverySlotId': order.get('deliverySlotId', ''),
        'discountCode': '',
        'additionalInfo': order.get('additionalInfo', ''),
    }
}

print(json.dumps(variables, ensure_ascii=False))
" "$ORDER_JSON" "$ORDER_ID" "$PACKAGING_EAN" "$@")

    RESPONSE=$(send_update "$ORDER_ID" "$VARS")
    parse_update_response "$RESPONSE"
    ;;

  # ---- REPLACE ----------------------------------------------
  # Replace the ENTIRE cart with given items
  # Usage: prisma-edit-order.sh replace <orderId> <ean:qty> [ean:qty...]
  replace)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh replace <orderId> <ean:qty> [ean:qty...]}"
    shift
    if [ $# -eq 0 ]; then
      echo "Error: At least one ean:qty pair required" >&2
      exit 1
    fi

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    echo "Replacing entire cart with $# item(s)..." >&2

    VARS=$(python3 -c "
import json, sys

order = json.loads(sys.argv[1])
order_id = sys.argv[2]
packaging_ean = sys.argv[3]
new_pairs = sys.argv[4:]

# Build fresh cart from provided pairs only — format: ean:qty[:r]
cart_items = []
for pair in new_pairs:
    parts = pair.split(':')
    if len(parts) not in (2, 3):
        print(f'Error: Invalid format \"{pair}\". Use ean:quantity or ean:quantity:r', file=sys.stderr)
        sys.exit(1)
    qty = int(parts[1])
    if qty <= 0:
        continue
    allow_replace = len(parts) == 3 and parts[2] == 'r'
    cart_items.append({
        'additionalInfo': '',
        'basicQuantityUnit': 'KPL',
        'ean': parts[0],
        'itemCount': str(qty),
        'replace': allow_replace,
    })

# Append packaging item
cart_items.append({
    'additionalInfo': '',
    'basicQuantityUnit': 'KPL',
    'ean': packaging_ean,
    'itemCount': '1',
    'replace': False,
})

# Build customer from fetched order
customer = order.get('customer', {})
geo = customer.get('geocodedAddress', {})
pos = geo.get('position', {}) if geo else {}
customer_input = {
    'companyName': customer.get('companyName'),
    'companyIdentityCode': customer.get('companyIdentityCode'),
    'email': customer.get('email', ''),
    'firstName': customer.get('firstName', ''),
    'lastName': customer.get('lastName', ''),
    'phone': customer.get('phone', ''),
    'invoiceNumber': customer.get('invoiceNumber', ''),
    'addressLine1': customer.get('addressLine1', ''),
    'addressLine2': customer.get('addressLine2'),
    'city': customer.get('city', 'Tallinn'),
    'postalCode': customer.get('postalCode', ''),
}
if pos:
    customer_input['addressCoordinates'] = {
        'latitude': pos.get('lat'),
        'longitude': pos.get('lng'),
    }

variables = {
    'id': order_id,
    'order': {
        'cartItems': cart_items,
        'customer': customer_input,
        'paymentMethod': 'CARD_PAYMENT',
        'storeId': order.get('storeId', ''),
        'reservationId': None,
        'deliverySlotId': order.get('deliverySlotId', ''),
        'discountCode': '',
        'additionalInfo': order.get('additionalInfo', ''),
    }
}

print(json.dumps(variables, ensure_ascii=False))
" "$ORDER_JSON" "$ORDER_ID" "$PACKAGING_EAN" "$@")

    RESPONSE=$(send_update "$ORDER_ID" "$VARS")
    parse_update_response "$RESPONSE"
    ;;

  # ---- SLOT -------------------------------------------------
  # Change the delivery slot on an already-placed order.
  # Reserves the new slot, then submits UpdateOrder with the new
  # deliverySlotId + reservationId, keeping all cart items unchanged.
  # Usage: prisma-edit-order.sh slot <orderId> <newSlotId>
  # Example slotId: 2026-05-16:fb59c2e3-4ea0-4036-9939-cc0336a09e49
  # Use prisma-checkout.sh slots <YYYY-MM-DD> to find slotIds.
  slot)
    ORDER_ID="${1:?Usage: prisma-edit-order.sh slot <orderId> <newSlotId>}"
    NEW_SLOT_ID="${2:?Usage: prisma-edit-order.sh slot <orderId> <newSlotId>}"

    echo "Reserving new slot $NEW_SLOT_ID..." >&2
    RESERVE_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'operationName': 'CreateDeliverySlotReservation',
    'variables': {'deliverySlotId': '$NEW_SLOT_ID'},
    'extensions': {'persistedQuery': {'version': 1, 'sha256Hash': '72d087d3d473c29bed2918464987f64aa4a9dab9d3afdc534aee168e8815dbee'}},
}))
")
    RESERVE_RESPONSE=$(printf '%s' "$RESERVE_PAYLOAD" | curl_auth -X POST "$API" \
      -H 'Content-Type: application/json' -d @-)

    RESERVATION_ID=$(python3 -c "
import json, sys
data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        print('ERROR: ' + e.get('message', str(e)), file=sys.stderr)
    sys.exit(1)
print(data['data']['createDeliverySlotReservation']['reservationId'])
" "$RESERVE_RESPONSE")

    if [ -z "$RESERVATION_ID" ]; then
      echo "Failed to reserve slot." >&2
      exit 1
    fi
    echo "Reserved: $RESERVATION_ID" >&2

    echo "Fetching order $ORDER_ID..." >&2
    RESPONSE=$(fetch_order "$ORDER_ID")
    ORDER_JSON=$(parse_order "$RESPONSE")

    echo "Submitting UpdateOrder with new slot..." >&2

    VARS=$(python3 -c "
import json, sys

order = json.loads(sys.argv[1])
order_id = sys.argv[2]
packaging_ean = sys.argv[3]
new_slot_id = sys.argv[4]
reservation_id = sys.argv[5]

# Preserve cart items as-is (only the slot is changing)
cart_items = []
for item in order.get('cartItems', []):
    ean = item['ean']
    if ean == packaging_ean or item.get('productType') != 'PRODUCT':
        continue
    cart_items.append({
        'additionalInfo': item.get('additionalInfo', '') or '',
        'basicQuantityUnit': item.get('basicQuantityUnit', 'KPL'),
        'ean': ean,
        'itemCount': str(item.get('itemCount', 1)),
        'replace': item.get('replace', False),
    })

# Append packaging
cart_items.append({
    'additionalInfo': '',
    'basicQuantityUnit': 'KPL',
    'ean': packaging_ean,
    'itemCount': '1',
    'replace': False,
})

# Build customer
customer = order.get('customer', {})
geo = customer.get('geocodedAddress', {})
pos = geo.get('position', {}) if geo else {}
customer_input = {
    'companyName': customer.get('companyName'),
    'companyIdentityCode': customer.get('companyIdentityCode'),
    'email': customer.get('email', ''),
    'firstName': customer.get('firstName', ''),
    'lastName': customer.get('lastName', ''),
    'phone': customer.get('phone', ''),
    'invoiceNumber': customer.get('invoiceNumber', ''),
    'addressLine1': customer.get('addressLine1', ''),
    'addressLine2': customer.get('addressLine2'),
    'city': customer.get('city', 'Tallinn'),
    'postalCode': customer.get('postalCode', ''),
}
if pos:
    customer_input['addressCoordinates'] = {
        'latitude': pos.get('lat'),
        'longitude': pos.get('lng'),
    }

variables = {
    'id': order_id,
    'order': {
        'cartItems': cart_items,
        'customer': customer_input,
        'paymentMethod': 'CARD_PAYMENT',
        'storeId': order.get('storeId', ''),
        'reservationId': reservation_id,
        'deliverySlotId': new_slot_id,
        'discountCode': '',
        'additionalInfo': order.get('additionalInfo', '') or '',
    }
}

print(json.dumps(variables, ensure_ascii=False))
" "$ORDER_JSON" "$ORDER_ID" "$PACKAGING_EAN" "$NEW_SLOT_ID" "$RESERVATION_ID")

    RESPONSE=$(send_update "$ORDER_ID" "$VARS")
    parse_update_response "$RESPONSE"
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage:" >&2
    echo "  prisma-edit-order.sh show <orderId>                        — show current items" >&2
    echo "  prisma-edit-order.sh add <orderId> <ean:qty> [ean:qty...]  — add items" >&2
    echo "  prisma-edit-order.sh remove <orderId> <ean> [ean...]       — remove items" >&2
    echo "  prisma-edit-order.sh set <orderId> <ean:qty> [ean:qty...]  — set exact quantities" >&2
    echo "  prisma-edit-order.sh replace <orderId> <ean:qty> [...]     — replace entire cart" >&2
    echo "  prisma-edit-order.sh slot <orderId> <newSlotId>            — change delivery slot" >&2
    exit 1
    ;;
esac