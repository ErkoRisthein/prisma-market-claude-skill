# Prisma Market Plugin

Claude Code plugin for grocery shopping at Prisma Market (prismamarket.ee).

## Structure

- **Marketplace manifest** (`.claude-plugin/marketplace.json`) — lists the plugin for `claude plugin marketplace add`
- **Plugin** (`prisma-market/`) — the installable plugin
- **Skill** (`prisma-market/skills/prisma/SKILL.md`) — describes the workflow and tools
- **API scripts** (`prisma-market/skills/prisma/scripts/`) — bash + curl + python3 wrappers around Prisma's GraphQL API

## Key technical details

- Prisma's GraphQL API requires browser-like headers (`Origin`, `Referer`, `User-Agent`) but no authentication
- Cart is client-side only — stored in `localStorage('cart-data')` as `ClientCartItem` objects
- Cookie consent (Usercentrics) is bypassed by modifying `uc_user_interaction` and `uc_settings` in localStorage
- Default store: Kristiine Prisma (`542860184`)
- Favorites API uses Apollo persisted queries (sha256 hashes), requires JWT auth
