---
name: prisma
description: >
  Grocery shopping at Prisma Market (prismamarket.ee). Use when the user wants to search for products,
  build a shopping cart, buy groceries, check out, or manage favorites at Prisma. Supports product search,
  price comparison, cart validation, direct API ordering, and managing favorites (add/remove/list).
allowed-tools: Bash(*prisma-*.sh*)
---

# Prisma Market Grocery Shopping

Help the user search for groceries at Prisma Market and order via the API.

All scripts are in the `scripts/` directory relative to this file.

## Workflow

### 1. Search for products

```bash
prisma-search.sh "<search term>" [limit] [storeId]
```

- Default limit: 10, store from `.env` or arg
- Returns: name, EAN, price, comparison price/unit, category, product URL

Present results as a clear table with name, price, and comparison price so the user can choose.

### 2. Get product details

```bash
prisma-product.sh <ean>
```

### 3. List available stores

```bash
prisma-stores.sh
```

### 4. Validate cart

Before ordering, validate availability and get current prices:

```bash
prisma-validate-cart.sh [storeId] <ean1:qty1> [ean2:qty2] ...
```

Returns availability, current/campaign prices, and estimated total.

### 5. Authenticate

Authentication credentials and tokens are stored in `.env` in the project root (gitignored):

```env
PRISMA_STORE_ID=542860184          # default store (Kristiine Prisma)
PRISMA_AUTH_METHOD=smart-id        # smart-id | mobile-id | id-card
PRISMA_PERSONAL_CODE=<isikukood>   # required for all methods
PRISMA_PHONE=<phone>               # required only for mobile-id
PRISMA_TOKEN=<jwt>                 # set automatically after login
```

**Check if already authenticated**: Run `prisma-auth.sh check`. If valid, skip login.

**Automated login flow** (when token is missing or expired):

1. Run `prisma-auth.sh login` to generate Playwright code, then execute it via `browser_run_code`:
   - The script reads credentials from `.env` and generates a Playwright snippet that navigates to prismamarket.ee, checks for existing session, clicks through the login flow, fills the form, and submits
   - Returns `{ status: 'already_logged_in', token }` if session exists, or `{ status: 'verification_needed', code }` with the Smart-ID/Mobiil-ID verification code
2. Show the verification code to the user so they can confirm on their device
3. Run `prisma-auth.sh login-complete` via `browser_run_code` to wait for the redirect and extract the token
   - Returns `{ status: 'success', token }`
4. Save the token: `prisma-auth.sh set <token>`

**Other auth commands**:
```bash
prisma-auth.sh check    # check token validity
prisma-auth.sh decode   # show token payload
prisma-auth.sh clear    # remove token from .env
```

### 6. Checkout via API (home delivery)

This is the **primary ordering method** — pure API, no browser needed.

#### 6a. List delivery slots

```bash
# Show available dates
prisma-checkout.sh slots

# Show time slots for a specific date
prisma-checkout.sh slots <YYYY-MM-DD> [postalCode]
```

#### 6b. Reserve a delivery slot

```bash
prisma-checkout.sh reserve <slotId>
```

Returns `{ reservationId, expiresAt, slotId }`. Reservation expires after 15 minutes.

#### 6c. Place order

```bash
# With explicit reservation and slot:
prisma-checkout.sh order <reservationId> <slotId> <ean1:qty1> [ean2:qty2] ...

# With env defaults (PRISMA_RESERVATION_ID, PRISMA_SLOT_ID):
prisma-checkout.sh order <ean1:qty1> [ean2:qty2] ...
```

- Cart items are sent directly in the API call — no browser cart needed
- Uses `CARD_PAYMENT` payment method
- Delivery address, contact info read from `.env`
- Returns full order details including orderNumber, orderStatus, cartItems with prices
- Order is created with `paymentStatus: PENDING` — use the `pay` subcommand to complete payment

#### 6d. List saved payment cards

```bash
prisma-checkout.sh cards
```

Returns saved cards with id, type, masked number, expiry, and default status.

#### 6e. Pay for an order with saved card

```bash
# Uses default saved card:
prisma-checkout.sh pay <orderId>

# With specific card:
prisma-checkout.sh pay <orderId> <cardId>
```

- Outputs Playwright code — run it via `browser_run_code`
- For saved cards, payment completes automatically (frictionless 3DS, no user interaction)
- Returns `{ status: 'success', orderId, url }` on success

**Full end-to-end flow**:
```bash
# 1. Validate items
prisma-validate-cart.sh 2060673000002:1 4740012345678:2

# 2. Check auth
prisma-auth.sh check

# 3. Find a delivery slot
prisma-checkout.sh slots 2026-03-05

# 4. Reserve it
prisma-checkout.sh reserve "2026-03-05:uuid-here"

# 5. Place order
prisma-checkout.sh order "RESERVATION#uuid" "2026-03-05:uuid-here" 2060673000002:1 4740012345678:2

# 6. Pay with saved card (run output via browser_run_code)
prisma-checkout.sh pay "<orderId>"
```

Additional `.env` variables for checkout:
```env
PRISMA_FIRST_NAME=Jaan
PRISMA_LAST_NAME=Tamm
PRISMA_PHONE=+37255512345
PRISMA_EMAIL=jaan.tamm@example.com
PRISMA_DELIVERY_ADDRESS="Pärnu mnt 10, 10148 Tallinn"
PRISMA_APARTMENT=42
PRISMA_DRIVER_INFO="3. korrus"
```

### 7. Alternative: Populate browser cart only

If the user prefers to review and checkout manually in the browser, use the cart-based flow:

```bash
prisma-cart.sh populate [storeId] <ean1:qty1> [ean2:qty2] ...
```

- Fetches product details for all EANs, builds `ClientCartItem` objects, and outputs Playwright code
- Prints a cart summary (items, prices, total) to stderr
- The Playwright code navigates to prismamarket.ee, bypasses cookie consent, writes cart data to `localStorage`, and navigates to `/kokkuvote`
- Run the output via `browser_run_code` — returns `{ success: true, itemCount: N }`
- Leave the browser open for the user to review and complete checkout manually

### 8. Manage favorites

Favorites require authentication (see step 5).

```bash
# List all favorites (returns array of EANs)
prisma-favorite.sh list

# Add a product to favorites by EAN
prisma-favorite.sh add <ean>

# Remove a product from favorites by EAN
prisma-favorite.sh remove <ean>
```

### 9. Order history

Order history requires authentication (see step 5).

```bash
# List recent orders
prisma-orders.sh list [limit]

# Get order details with cart items
prisma-orders.sh detail <orderId>

# Get just ean:qty pairs from an order (for re-ordering or exclusion)
prisma-orders.sh items <orderId>
```

Use order history to vary product selections — check recent orders and avoid re-ordering the same items.

## Conversational guidelines

- When the user asks to buy something, search for it first and present options
- Always show prices and comparison prices (price per kg/L) to help the user choose
- If a product search returns many results, help the user narrow down
- Default store is configured in `.env` (`PRISMA_STORE_ID`) — ask the user if they want a different store
- **Prefer the API checkout flow** (step 6) over the browser cart flow (step 7) unless the user specifically asks to use the browser

### Order safety rules

- **Always validate before ordering**: Run `prisma-validate-cart.sh` before every order — never skip this step
- **Confirm with user**: Show the full item list with prices and estimated total, and get explicit confirmation before placing an order
- **No duplicate EANs**: If the same product appears twice, merge into a single entry with combined quantity
- **Track cart state**: Keep track of what's been added during the conversation so you can include previous items when the user adds more
