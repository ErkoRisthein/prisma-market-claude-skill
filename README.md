# Prisma Market Claude Code Skill

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill for shopping groceries at [Prisma Market](https://www.prismamarket.ee) — search products, build a cart, and open it in the browser ready for checkout.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `curl` and `python3` available in your shell
- [Playwright MCP](https://github.com/anthropics/claude-code/blob/main/docs/mcp.md) plugin installed in Claude Code (used to populate the cart in the browser)

### Installing Playwright MCP

If you don't have the Playwright MCP plugin yet:

```bash
claude mcp add playwright -- npx @anthropic-ai/claude-code-playwright@latest
```

## Install

Clone this repo and add it as a skill source in your project's `.claude/settings.json`:

```json
{
  "skills": [
    "/path/to/prisma-market-claude-skill/skills/prisma"
  ]
}
```

Or add it directly via Claude Code:

```
/skill add /path/to/prisma-market-claude-skill/skills/prisma
```

## Usage

Once installed, just ask Claude to shop at Prisma:

- *"I need milk, bread, and cheese from Prisma"*
- *"Search for yogurt at Prisma Market"*
- *"Add 2 cartons of Farmi piim to my Prisma cart"*
- *"Open my Prisma cart in the browser"*

Claude will search for products, confirm your choices, build a cart, and open it in your browser at prismamarket.ee/kokkuvote — ready for you to review and checkout.

## How it works

1. **Product search** — queries Prisma's GraphQL API via bash scripts (`curl` + `python3`)
2. **Cart building** — tracks your selected products and quantities in conversation
3. **Browser cart population** — uses Playwright MCP to write cart items to `localStorage` on prismamarket.ee, then navigates to the cart summary page
4. **Checkout** — you take over in the browser to log in, select delivery, and pay

## Scripts

| Script | Purpose |
|--------|---------|
| `prisma-search.sh <term> [limit] [storeId]` | Search products by keyword |
| `prisma-product.sh <ean>` | Get details for a single product |
| `prisma-stores.sh` | List all Prisma stores in Estonia |
| `prisma-validate-cart.sh <storeId> <ean1:qty1> [ean2:qty2 ...]` | Validate cart items and check availability |

## Project structure

```
skills/prisma/
  SKILL.md              # Skill definition (triggers, allowed tools, workflow)
  scripts/
    prisma-search.sh    # Product search
    prisma-product.sh   # Single product lookup
    prisma-stores.sh    # Store listing
    prisma-validate-cart.sh  # Cart validation
```

## Default store

The default store is **Kristiine Prisma** (ID: `542860184`). You can ask Claude to use a different store — run `prisma-stores.sh` to see all available stores.

## License

MIT
