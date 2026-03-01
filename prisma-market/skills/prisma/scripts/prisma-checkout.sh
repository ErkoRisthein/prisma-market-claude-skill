#!/usr/bin/env bash
# Pure API checkout for Prisma Market
# Usage:
#   prisma-checkout.sh slots [date] [postalCode]       — list delivery slots
#   prisma-checkout.sh reserve <slotId>                 — reserve a delivery slot
#   prisma-checkout.sh order <ean1:qty1> [ean2:qty2]... — place order
#   prisma-checkout.sh cards                            — list saved payment cards
#   prisma-checkout.sh pay <orderId> [cardId]           — pay with saved card (outputs Playwright code)
#
# Reads from .env:
#   PRISMA_TOKEN — JWT auth token (required for reserve + order)
#   PRISMA_STORE_ID — store ID (default: 542860184)
#   PRISMA_DELIVERY_ADDRESS, PRISMA_APARTMENT
#   PRISMA_FIRST_NAME, PRISMA_LAST_NAME, PRISMA_PHONE, PRISMA_EMAIL
#   PRISMA_DRIVER_INFO — optional note for driver

set -euo pipefail

source "$(dirname "$0")/_env.sh"

API="https://graphql-api.prismamarket.ee"
STORE_ID="${PRISMA_STORE_ID:-542860184}"

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

# Persisted query via GET
persisted_get() {
  local op="$1" vars="$2" hash="$3"
  local encoded_vars encoded_ext
  encoded_vars=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$vars'))")
  encoded_ext=$(python3 -c "import urllib.parse,json; print(urllib.parse.quote(json.dumps({'persistedQuery':{'version':1,'sha256Hash':'$hash'}})))")
  curl_common "$API/?operationName=$op&variables=$encoded_vars&extensions=$encoded_ext"
}

# Persisted query via POST (for mutations)
persisted_post() {
  local op="$1" vars="$2" hash="$3"
  local payload
  payload=$(python3 -c "
import json
print(json.dumps({
    'operationName': '$op',
    'variables': json.loads('$vars'),
    'extensions': {'persistedQuery': {'version': 1, 'sha256Hash': '$hash'}}
}))
")
  printf '%s' "$payload" | curl_auth -X POST "$API" \
    -H 'Content-Type: application/json' \
    -d @-
}

ACTION="${1:?Usage: prisma-checkout.sh [slots|reserve|order] ...}"
shift

case "$ACTION" in

  # ─── SLOTS ─────────────────────────────────────────────
  # List available delivery time slots
  # Usage: prisma-checkout.sh slots [date] [postalCode]
  #   date: YYYY-MM-DD (default: tomorrow through +28 days)
  #   postalCode: postal code (default: from PRISMA_DELIVERY_ADDRESS)
  slots)
    DATE="${1:-}"
    POSTAL="${2:-}"

    # Extract postal code from address if not specified
    if [ -z "$POSTAL" ]; then
      ADDR="${PRISMA_DELIVERY_ADDRESS:-}"
      if [ -n "$ADDR" ]; then
        REST="${ADDR#*,}"
        REST="${REST# }"
        POSTAL="${REST%% *}"
      fi
      POSTAL="${POSTAL:-10113}"
    fi

    if [ -n "$DATE" ]; then
      # Show slots for a specific date
      echo "Fetching delivery slots for $DATE (postal: $POSTAL)..." >&2
      VARS="{\"startDate\":\"$DATE\",\"endDate\":\"$DATE\",\"postalCode\":\"$POSTAL\"}"
      RESPONSE=$(persisted_get "remoteHomeDeliverySlots" "$VARS" "22936033f0c090d6b38319242bf692b11f75240bd7301ad597bdc3da94741236")
    else
      # Show date availability first
      START=$(date -v+1d +%Y-%m-%d 2>/dev/null || date -d '+1 day' +%Y-%m-%d)
      END=$(date -v+28d +%Y-%m-%d 2>/dev/null || date -d '+28 days' +%Y-%m-%d)
      echo "Fetching slot availability $START to $END (postal: $POSTAL)..." >&2
      VARS="{\"startDate\":\"$START\",\"endDate\":\"$END\",\"postalCode\":\"$POSTAL\"}"
      RESPONSE=$(persisted_get "remoteHomeDeliveryAvailabilities" "$VARS" "77fa47f0c48d94bdb71478be5122265403488a315ebbcc01eeef775a705913d0")
    fi

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        print('ERROR: ' + e.get('message', str(e)), file=sys.stderr)
    sys.exit(1)

d = data.get('data', {})

# Date availability response
avail = d.get('homeDeliverySlotAvailabilitiesForPostalCode', {}).get('availabilities')
if avail is not None:
    dates = [a for a in avail if a['available']]
    result = {'availableDates': [a['date'] for a in dates], 'totalAvailable': len(dates)}
    print(json.dumps(result, indent=2))
    sys.exit(0)

# Slot details response
stores = d.get('homeDeliverySlotsForPostalCode', {}).get('homeDeliverySlotsInStores', [])
result = []
for store in stores:
    info = store.get('groupInfo', {})
    for slot in store.get('slots', []):
        result.append({
            'slotId': slot['id'],
            'store': info.get('storeName', ''),
            'storeId': info.get('storeId', ''),
            'areaId': (info.get('deliveryAreaIds') or [''])[0],
            'start': slot['deliveryTimeStart'],
            'end': slot['deliveryTimeEnd'],
            'price': slot['price'],
            'closingTime': slot['closingTime'],
            'alcoholAllowed': slot.get('isAlcoholSellingAllowed', False)
        })
print(json.dumps(result, indent=2))
" "$RESPONSE"
    ;;

  # ─── RESERVE ───────────────────────────────────────────
  # Reserve a delivery slot (requires auth)
  # Usage: prisma-checkout.sh reserve <slotId>
  reserve)
    SLOT_ID="${1:?Usage: prisma-checkout.sh reserve <slotId>}"

    echo "Reserving slot $SLOT_ID..." >&2

    VARS="{\"deliverySlotId\":\"$SLOT_ID\"}"
    RESPONSE=$(persisted_post "CreateDeliverySlotReservation" "$VARS" "72d087d3d473c29bed2918464987f64aa4a9dab9d3afdc534aee168e8815dbee")

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        print('ERROR: ' + e.get('message', str(e)), file=sys.stderr)
    sys.exit(1)

reservation = data['data']['createDeliverySlotReservation']
print(json.dumps({
    'reservationId': reservation['reservationId'],
    'expiresAt': reservation['expiresAt'],
    'slotId': sys.argv[2]
}, indent=2))
" "$RESPONSE" "$SLOT_ID"
    ;;

  # ─── ORDER ─────────────────────────────────────────────
  # Place an order (requires auth + active slot reservation)
  # Usage: prisma-checkout.sh order <reservationId> <slotId> <ean1:qty1> [ean2:qty2] ...
  #
  # Or with env defaults:
  #   prisma-checkout.sh order <ean1:qty1> [ean2:qty2] ...
  #   (uses PRISMA_RESERVATION_ID, PRISMA_SLOT_ID from .env)
  order)
    # Parse arguments: either (reservationId slotId items...) or just (items...)
    if [[ "${1:-}" == RESERVATION#* ]]; then
      RESERVATION_ID="$1"; shift
      SLOT_ID="${1:?Missing slotId}"; shift
    else
      RESERVATION_ID="${PRISMA_RESERVATION_ID:?Set PRISMA_RESERVATION_ID or pass as first arg}"
      SLOT_ID="${PRISMA_SLOT_ID:?Set PRISMA_SLOT_ID or pass as second arg}"
    fi

    if [ $# -eq 0 ]; then
      echo "Error: At least one ean:quantity pair required" >&2
      exit 1
    fi

    : "${PRISMA_LAST_NAME:?Set PRISMA_LAST_NAME in .env}"
    : "${PRISMA_PHONE:?Set PRISMA_PHONE in .env}"
    : "${PRISMA_EMAIL:?Set PRISMA_EMAIL in .env}"
    : "${PRISMA_DELIVERY_ADDRESS:?Set PRISMA_DELIVERY_ADDRESS in .env}"

    FIRST_NAME="${PRISMA_FIRST_NAME:-}"
    APARTMENT="${PRISMA_APARTMENT:-}"
    DRIVER_INFO="${PRISMA_DRIVER_INFO:-}"

    # Parse address: "Lastekodu 31/1, 10113 Tallinn"
    STREET="${PRISMA_DELIVERY_ADDRESS%%,*}"
    REST="${PRISMA_DELIVERY_ADDRESS#*,}"
    REST="${REST# }"
    POSTAL_CODE="${REST%% *}"
    CITY="${REST#* }"

    echo "Placing order: $# item(s), slot $SLOT_ID" >&2

    # Build order payload
    PAYLOAD=$(python3 -c "
import json, sys

reservation_id = sys.argv[1]
slot_id = sys.argv[2]
store_id = sys.argv[3]
first_name = sys.argv[4]
last_name = sys.argv[5]
phone = sys.argv[6]
email = sys.argv[7]
street = sys.argv[8]
apartment = sys.argv[9]
postal_code = sys.argv[10]
city = sys.argv[11]
driver_info = sys.argv[12]
ean_qty_pairs = sys.argv[13:]

# Build cart items — itemCount must be String per GraphQL schema
cart_items = []
for pair in ean_qty_pairs:
    parts = pair.split(':')
    if len(parts) != 2:
        print(f'Error: Invalid format \"{pair}\". Use ean:quantity', file=sys.stderr)
        sys.exit(1)
    cart_items.append({
        'ean': parts[0],
        'itemCount': parts[1],
        'replace': True
    })

order_input = {
    'storeId': store_id,
    'customer': {
        'firstName': first_name or None,
        'lastName': last_name,
        'phone': phone,
        'email': email,
        'addressLine1': street,
        'addressLine2': apartment or None,
        'postalCode': postal_code,
        'city': city
    },
    'cartItems': cart_items,
    'reservationId': reservation_id,
    'deliverySlotId': slot_id,
    'paymentMethod': 'CARD_PAYMENT',
    'additionalInfo': driver_info or None,
    'discountCode': None
}

mutation = '''mutation CreateOrder(\$order: OrderInput) {
  createOrder(order: \$order) {
    id
    orderNumber
    orderStatus
    deliveryDate
    deliveryTime
    deliverySlotId
    deliveryMethod
    homeDeliveryType
    paymentMethod
    paymentStatus
    storeId
    accessToken
    additionalInfo
    customer {
      firstName
      lastName
      phone
      email
      addressLine1
      addressLine2
      postalCode
      city
    }
    cartItems {
      ean
      name
      itemCount
      price
      replace
      priceUnit
      basicQuantityUnit
    }
  }
}'''

print(json.dumps({
    'operationName': 'CreateOrder',
    'query': mutation,
    'variables': {'order': order_input}
}))
" "$RESERVATION_ID" "$SLOT_ID" "$STORE_ID" \
  "$FIRST_NAME" "$PRISMA_LAST_NAME" "$PRISMA_PHONE" "$PRISMA_EMAIL" \
  "$STREET" "$APARTMENT" "$POSTAL_CODE" "$CITY" \
  "$DRIVER_INFO" \
  "$@")

    RESPONSE=$(printf '%s' "$PAYLOAD" | curl_auth -X POST "$API" \
      -H 'Content-Type: application/json' \
      -d @-)

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
        # Show validation errors if any
        for ve in ext.get('validationErrors', []):
            print(f'  - {ve.get(\"path\", [])}: {ve.get(\"message\", \"\")}', file=sys.stderr)
    sys.exit(1)

order = data.get('data', {}).get('createOrder')
if not order:
    print('No order data returned', file=sys.stderr)
    print(json.dumps(data, indent=2), file=sys.stderr)
    sys.exit(1)

# Clean output
result = {k: v for k, v in order.items() if v is not None and k != '__typename'}
if 'cartItems' in result:
    result['cartItems'] = [{k: v for k, v in item.items() if v is not None and k != '__typename'} for item in result['cartItems']]
if 'customer' in result:
    result['customer'] = {k: v for k, v in result['customer'].items() if v is not None and k != '__typename'}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$RESPONSE"
    ;;

  # ─── CARDS ────────────────────────────────────────────
  # List saved payment cards (requires auth)
  cards)
    PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'operationName': 'GetUserPaymentCards',
    'query': 'query GetUserPaymentCards(\$storeId: ID) { userPaymentCards(storeId: \$storeId) { cards { id maskedCardNumber name expiryDate type userGeneratedName expiryStatus } defaultPaymentCardId } }',
    'variables': {'storeId': '$STORE_ID'}
}))
")
    RESPONSE=$(printf '%s' "$PAYLOAD" | curl_auth -X POST "$API" \
      -H 'Content-Type: application/json' \
      -d @-)

    python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors', [])
if errors:
    for e in errors:
        print('ERROR: ' + e.get('message', str(e)), file=sys.stderr)
    sys.exit(1)

cards_data = data['data']['userPaymentCards']
default_id = cards_data.get('defaultPaymentCardId')
result = []
for card in cards_data.get('cards', []):
    c = {
        'id': card['id'],
        'type': card['type'],
        'maskedNumber': card['maskedCardNumber'],
        'name': card.get('userGeneratedName') or card['name'],
        'expiryDate': card['expiryDate'],
        'expiryStatus': card['expiryStatus'],
        'isDefault': card['id'] == default_id
    }
    result.append(c)
print(json.dumps(result, indent=2))
" "$RESPONSE"
    ;;

  # ─── PAY ─────────────────────────────────────────────
  # Pay for an order with saved card (outputs Playwright code)
  # Usage: prisma-checkout.sh pay <orderId> [cardId]
  # If cardId is omitted, uses the default saved card.
  # Outputs Playwright code for browser_run_code that navigates through
  # the Nets 3DS redirect (automatic for saved cards, no user interaction).
  pay)
    ORDER_ID="${1:?Usage: prisma-checkout.sh pay <orderId> [cardId]}"
    CARD_ID="${2:-}"

    # If no card ID provided, fetch default card
    if [ -z "$CARD_ID" ]; then
      CARDS_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'operationName': 'GetUserPaymentCards',
    'query': 'query GetUserPaymentCards(\$storeId: ID) { userPaymentCards(storeId: \$storeId) { cards { id } defaultPaymentCardId } }',
    'variables': {'storeId': '$STORE_ID'}
}))
")
      CARD_ID=$(printf '%s' "$CARDS_PAYLOAD" | curl_auth -X POST "$API" \
        -H 'Content-Type: application/json' \
        -d @- | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
cards_data = data.get('data', {}).get('userPaymentCards', {})
default_id = cards_data.get('defaultPaymentCardId')
if default_id:
    print(default_id)
elif cards_data.get('cards'):
    print(cards_data['cards'][0]['id'])
else:
    print('No saved payment cards found', file=sys.stderr)
    sys.exit(1)
")
      echo "Using default card: $CARD_ID" >&2
    fi

    # Call CreatePayment to get redirect URL
    PAY_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'operationName': 'CreatePayment',
    'query': 'mutation CreatePayment(\$orderId: ID!, \$device: DeviceType!, \$customWebstoreRedirectUrl: String, \$cardId: ID, \$shouldSavePaymentCard: Boolean) { createPayment(orderId: \$orderId, device: \$device, customWebstoreRedirectUrl: \$customWebstoreRedirectUrl, cardId: \$cardId, shouldSavePaymentCard: \$shouldSavePaymentCard) { redirectUrl } }',
    'variables': {
        'orderId': '$ORDER_ID',
        'device': 'DESKTOP',
        'cardId': '$CARD_ID',
        'shouldSavePaymentCard': False
    }
}))
")
    REDIRECT_URL=$(printf '%s' "$PAY_PAYLOAD" | curl_auth -X POST "$API" \
      -H 'Content-Type: application/json' \
      -d @- | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
errors = data.get('errors', [])
if errors:
    for e in errors:
        print('ERROR: ' + e.get('message', str(e)), file=sys.stderr)
    sys.exit(1)
print(data['data']['createPayment']['redirectUrl'])
")

    echo "Payment redirect URL obtained, generating Playwright code..." >&2

    # Output Playwright code that navigates through the Nets 3DS redirect
    # For saved cards, this is fully automatic (frictionless 3DS)
    cat <<PLAYWRIGHT
async (page) => {
  // Navigate to Nets payment gateway — saved cards auto-complete via frictionless 3DS
  // Don't wait for networkidle — 3DS iframes cause premature resolution
  await page.goto('$REDIRECT_URL', { waitUntil: 'domcontentloaded', timeout: 30000 });

  // Wait for the redirect chain: Nets → 3DS → /payment/auth/ → /tellimus/
  // This takes 5-15 seconds for saved cards (frictionless 3DS)
  try {
    await page.waitForURL(/tellimus/, { timeout: 30000 });
    return { status: 'success', orderId: '$ORDER_ID', url: page.url() };
  } catch (e) {
    const url = page.url();
    if (url.includes('/payment/auth/')) {
      return { status: 'auth_pending', orderId: '$ORDER_ID', url };
    }
    // Still on Nets or 3DS page — may need user interaction
    return { status: 'needs_interaction', orderId: '$ORDER_ID', url };
  }
}
PLAYWRIGHT
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage:" >&2
    echo "  prisma-checkout.sh slots [date] [postalCode]   — list delivery slots" >&2
    echo "  prisma-checkout.sh reserve <slotId>             — reserve a slot" >&2
    echo "  prisma-checkout.sh order [reservationId slotId] <ean:qty>... — place order" >&2
    echo "  prisma-checkout.sh cards                        — list saved payment cards" >&2
    echo "  prisma-checkout.sh pay <orderId> [cardId]       — pay with saved card" >&2
    exit 1
    ;;
esac
