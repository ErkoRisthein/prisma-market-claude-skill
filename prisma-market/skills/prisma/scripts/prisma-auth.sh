#!/usr/bin/env bash
# Manage Prisma Market auth tokens
# Usage:
#   prisma-auth.sh login             — output Playwright JS to automate login (use with browser_run_code)
#   prisma-auth.sh login-complete    — output Playwright JS to wait for login & extract token
#   prisma-auth.sh set <token>       — save token to .env
#   prisma-auth.sh check             — check if saved token is still valid
#   prisma-auth.sh decode            — show saved token payload (user info, expiry)
#   prisma-auth.sh clear             — remove saved token
#
# Token is stored in .env in the project root (gitignored).
# All prisma scripts source this file automatically via _env.sh.

set -euo pipefail
source "$(dirname "$0")/_env.sh"

ACTION="${1:?Usage: prisma-auth.sh <login|login-complete|set|check|decode|clear> [token]}"

load_token() {
  if [ -n "${PRISMA_TOKEN:-}" ]; then
    echo "$PRISMA_TOKEN"
  else
    echo "No token found. Run: prisma-auth.sh set <token>" >&2
    exit 1
  fi
}

case "$ACTION" in
  login)
    AUTH_METHOD="${PRISMA_AUTH_METHOD:-smart-id}"
    PERSONAL_CODE="${PRISMA_PERSONAL_CODE:?PRISMA_PERSONAL_CODE not set in .env}"
    PHONE="${PRISMA_PHONE:-}"

    # Map auth method to tab name
    case "$AUTH_METHOD" in
      smart-id)  TAB_NAME="Smart-ID" ;;
      mobile-id) TAB_NAME="Mobiil-ID" ;;
      id-card)   TAB_NAME="ID-Kaart" ;;
      *) echo "Unknown auth method: $AUTH_METHOD" >&2; exit 1 ;;
    esac

    # Build phone fill line for mobile-id
    PHONE_FILL=""
    if [ "$AUTH_METHOD" = "mobile-id" ]; then
      [ -z "$PHONE" ] && { echo "PRISMA_PHONE not set in .env (required for mobile-id)" >&2; exit 1; }
      PHONE_FILL="await page.getByRole('textbox', { name: 'Telefoninumber' }).fill('$PHONE');"
    fi

    cat <<PLAYWRIGHT
async (page) => {
  await page.goto('https://www.prismamarket.ee', { waitUntil: 'domcontentloaded' });

  // Bypass Usercentrics cookie consent via localStorage
  await page.evaluate(() => {
    const raw = localStorage.getItem('uc_settings');
    if (raw) {
      const settings = JSON.parse(raw);
      const now = Date.now();
      settings.services.forEach(service => {
        const hasAccepted = service.history.some(h => h.action === 'onAcceptAllServices');
        if (!hasAccepted) {
          service.history.push({ action: 'onAcceptAllServices', language: 'et', status: true, timestamp: now, type: 'explicit', versions: service.history[0].versions });
        }
      });
      localStorage.setItem('uc_settings', JSON.stringify(settings));
    }
    localStorage.setItem('uc_user_interaction', 'true');
  });

  // Check if already logged in
  const existingToken = await page.evaluate(() => {
    const raw = localStorage.getItem('client-data');
    if (!raw) return null;
    const data = JSON.parse(raw);
    return data?.clientSession?.authTokens?.accessToken || null;
  });
  if (existingToken) return { status: 'already_logged_in', token: existingToken };

  // Click login
  await page.locator('[data-test-id="global-nav-login"]').click();
  await page.getByRole('button', { name: 'Logi ePrismasse' }).waitFor();
  await page.getByRole('button', { name: 'Logi ePrismasse' }).click();

  // Wait for login page
  await page.waitForURL(/login\\.prismamarket\\.ee/);

  // Dismiss cookie consent overlay on login page if present
  try {
    await page.getByRole('button', { name: 'Nõustuge' }).click({ timeout: 3000 });
  } catch (e) { /* not present */ }

  // Select auth method
  await page.getByRole('tab', { name: '$TAB_NAME' }).click();

  // Fill credentials
  await page.getByRole('textbox', { name: 'Isikukood' }).fill('$PERSONAL_CODE');
  $PHONE_FILL

  // Submit
  await page.getByRole('button', { name: 'Sisene' }).click();

  // Wait for verification code
  await page.waitForTimeout(2000);
  const codeEl = await page.locator('h1').nth(1);
  const code = await codeEl.textContent();

  return { status: 'verification_needed', code };
}
PLAYWRIGHT
    ;;

  login-complete)
    cat <<'PLAYWRIGHT'
async (page) => {
  // Wait for redirect back to prismamarket.ee (up to 2 minutes for user to confirm)
  await page.waitForURL('https://www.prismamarket.ee/**', { timeout: 120000 });
  await page.waitForLoadState('domcontentloaded');

  // Bypass Usercentrics cookie consent via localStorage
  await page.evaluate(() => {
    const raw = localStorage.getItem('uc_settings');
    if (raw) {
      const settings = JSON.parse(raw);
      const now = Date.now();
      settings.services.forEach(service => {
        const hasAccepted = service.history.some(h => h.action === 'onAcceptAllServices');
        if (!hasAccepted) {
          service.history.push({ action: 'onAcceptAllServices', language: 'et', status: true, timestamp: now, type: 'explicit', versions: service.history[0].versions });
        }
      });
      localStorage.setItem('uc_settings', JSON.stringify(settings));
      localStorage.setItem('uc_user_interaction', 'true');
    }
  });

  // Wait for auth data to settle in localStorage
  await page.waitForTimeout(2000);

  // Extract token
  const token = await page.evaluate(() => {
    const raw = localStorage.getItem('client-data');
    if (!raw) return null;
    const data = JSON.parse(raw);
    return data?.clientSession?.authTokens?.accessToken || null;
  });

  return token
    ? { status: 'success', token }
    : { status: 'error', message: 'No token found after login' };
}
PLAYWRIGHT
    ;;

  set)
    TOKEN="${2:?Usage: prisma-auth.sh set <token>}"
    # Update PRISMA_TOKEN in .env, preserving other fields
    if [ -f "$ENV_FILE" ]; then
      # Remove existing PRISMA_TOKEN line, then append new one
      grep -v '^PRISMA_TOKEN=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
      printf 'PRISMA_TOKEN=%s\n' "$TOKEN" >> "$ENV_FILE.tmp"
      mv "$ENV_FILE.tmp" "$ENV_FILE"
    else
      printf 'PRISMA_TOKEN=%s\n' "$TOKEN" > "$ENV_FILE"
    fi
    export PRISMA_TOKEN="$TOKEN"
    echo "Token saved to .env."

    # Validate it
    python3 -c "
import json, sys, base64, time

token = sys.argv[1]
parts = token.split('.')
if len(parts) != 3:
    print('Warning: not a valid JWT')
    sys.exit(0)

payload_b64 = parts[1]
payload_b64 += '=' * (4 - len(payload_b64) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_b64))

name = payload.get('firstName', '?')
exp = payload.get('exp')
if exp:
    remaining = exp - int(time.time())
    minutes = remaining // 60
    print('Logged in as: %s (%d minutes remaining)' % (name, minutes))
else:
    print('Logged in as:', name)
" "$TOKEN"
    ;;

  check)
    TOKEN="$(load_token)"

    python3 -c "
import json, sys, base64, time

token = sys.argv[1]
parts = token.split('.')
if len(parts) != 3:
    print('Error: not a valid JWT')
    sys.exit(1)

payload_b64 = parts[1]
payload_b64 += '=' * (4 - len(payload_b64) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_b64))

now = int(time.time())

# Check session expiry (sIdExp) first — session can expire before JWT
sid_exp = payload.get('sIdExp')
if sid_exp is not None:
    sid_remaining = sid_exp - now
    if sid_remaining <= 0:
        print('SESSION_EXPIRED (session expired %d seconds ago)' % abs(sid_remaining))
        sys.exit(1)

exp = payload.get('exp')
if exp is None:
    print('Warning: token has no exp claim')
    sys.exit(0)

remaining = exp - now

if remaining <= 0:
    print('EXPIRED (expired %d seconds ago)' % abs(remaining))
    sys.exit(1)

# Report the earliest expiry
effective = min(remaining, sid_remaining) if sid_exp is not None else remaining

if effective < 300:
    print('EXPIRING SOON (%d seconds remaining)' % effective)
    sys.exit(0)
else:
    minutes = effective // 60
    print('VALID (%d minutes remaining)' % minutes)
    sys.exit(0)
" "$TOKEN"
    ;;

  decode)
    TOKEN="$(load_token)"

    python3 -c "
import json, sys, base64

token = sys.argv[1]
parts = token.split('.')
if len(parts) != 3:
    print('Error: not a valid JWT (expected 3 dot-separated parts)')
    sys.exit(1)

payload_b64 = parts[1]
payload_b64 += '=' * (4 - len(payload_b64) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_b64))

print(json.dumps(payload, indent=2, ensure_ascii=False))
" "$TOKEN"
    ;;

  clear)
    if [ -f "$ENV_FILE" ]; then
      grep -v '^PRISMA_TOKEN=' "$ENV_FILE" > "$ENV_FILE.tmp" || true
      mv "$ENV_FILE.tmp" "$ENV_FILE"
    fi
    unset PRISMA_TOKEN 2>/dev/null || true
    echo "Token cleared."
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    echo "Usage: prisma-auth.sh <login|login-complete|set|check|decode|clear> [token]" >&2
    exit 1
    ;;
esac
