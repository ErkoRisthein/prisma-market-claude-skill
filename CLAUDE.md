# Prisma Market Skill

This repo contains a Claude Code skill for grocery shopping at Prisma Market (prismamarket.ee).

## Architecture

- **API scripts** (`skills/prisma/scripts/`) — bash + curl + python3 wrappers around Prisma's GraphQL API at `https://graphql-api.prismamarket.ee`
- **Cart population** — via Playwright MCP: write cart items to `localStorage('cart-data')` on prismamarket.ee, then navigate to `/kokkuvote`
- **Skill definition** (`skills/prisma/SKILL.md`) — describes the workflow and allowed tools for Claude Code

## Key technical details

- Prisma's GraphQL API requires browser-like headers (`Origin`, `Referer`, `User-Agent`) but no authentication
- Cart is client-side only — stored in `localStorage('cart-data')` as `ClientCartItem` objects
- Cookie consent (Usercentrics) is bypassed by modifying `uc_user_interaction` and `uc_settings` in localStorage
- Default store: Kristiine Prisma (`542860184`)
