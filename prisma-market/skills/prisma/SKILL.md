---
name: prisma
description: >
  Grocery shopping at Prisma Market (prismamarket.ee). Use when the user wants to search for products,
  build a shopping cart, buy groceries, or manage favorites at Prisma. Supports product search, price comparison,
  cart validation, populating the browser cart for checkout, and managing favorites (add/remove/list).
allowed-tools: Bash(*prisma-*.sh*)
---

# Prisma Market Grocery Shopping

Help the user search for groceries at Prisma Market and populate a shopping cart in the browser.

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

Before populating the browser cart, validate availability and get current prices:

```bash
prisma-validate-cart.sh <storeId> <ean1:qty1> [ean2:qty2] ...
```

Returns availability, current/campaign prices, and estimated total.

### 5. Populate cart in browser

Once the user confirms the items, generate and run Playwright code to populate the cart:

```bash
prisma-cart.sh populate [storeId] <ean1:qty1> [ean2:qty2] ...
```

- Fetches product details for all EANs, builds `ClientCartItem` objects, and outputs Playwright code
- Prints a cart summary (items, prices, total) to stderr
- The Playwright code navigates to prismamarket.ee, bypasses cookie consent, writes cart data to `localStorage`, and navigates to `/kokkuvote`
- Run the output via `browser_run_code` — returns `{ success: true, itemCount: N }`
Leave the browser open for the user to review and proceed to checkout.

### 6. Authenticate

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

Example:
```bash
# Step 1: generate login code and run via browser_run_code
prisma-auth.sh login
# → copy output to browser_run_code, returns verification code

# Step 2: show code to user, then wait for confirmation
prisma-auth.sh login-complete
# → copy output to browser_run_code, returns token

# Step 3: save the token
prisma-auth.sh set <token>
```

**Other auth commands**:
```bash
prisma-auth.sh check    # check token validity
prisma-auth.sh decode   # show token payload
prisma-auth.sh clear    # remove token from .env
```

### 7. Manage favorites

Favorites require authentication (see step 6).

```bash
# List all favorites (returns array of EANs)
prisma-favorite.sh list

# Add a product to favorites by EAN
prisma-favorite.sh add <ean>

# Remove a product from favorites by EAN
prisma-favorite.sh remove <ean>
```

### 8. Order history

Order history requires authentication (see step 6).

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

### Cart safety rules

- **Always validate before populating**: Run `prisma-validate-cart.sh` before every `prisma-cart.sh populate` — never skip this step
- **Confirm with user**: Show the full item list with prices and estimated total, and get explicit confirmation before populating the browser cart
- **Cart is replace-only**: `prisma-cart.sh populate` overwrites the entire cart. If the user wants to add items to an existing cart, include all previous items in the new populate call
- **No duplicate EANs**: If the same product appears twice, merge into a single entry with combined quantity
- **Track cart state**: Keep track of what's been added during the conversation so you can include previous items when the user adds more
