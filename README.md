
# Prisma Market

Shop for groceries at [Prisma Market](https://www.prismamarket.ee) via Claude Code.

## Install

```
/plugin marketplace add ErkoRisthein/prisma-market-claude-skill
/plugin install prisma-market
```

## Setup

Copy [`.env.example`](.env.example) to `.env` in your project root and fill in your values:

```bash
cp .env.example .env
```

See `.env.example` for all available variables (store, authentication, delivery details).

## Usage

> /prisma I need milk, eggs, and black bread

> /prisma It's Estonian Independence Day on Feb 24 and I'm having 6 friends over for dinner. Get me everything I need for a traditional Estonian meal.

> /prisma Find me ingredients for a proper carbonara for 4 people

> /prisma I'm doing a week of meal prep — buy chicken, rice, broccoli, eggs, and oatmeal. Enough for 5 days, 2 meals a day.

> /prisma What's the cheapest milk per liter right now?

> /prisma I'm starting keto — stock me up for a week. High fat, under 20g carbs per day.

> /prisma I'm lactose intolerant. Find me lactose-free alternatives for milk, yogurt, and cheese.

> /prisma I have 20 euros. Fill my cart with as much protein as possible — best price per kilo.

> /prisma Compare all the cheddar cheeses and pick the best value per kilo.

## Requirements

- [Playwright plugin](https://github.com/anthropics/claude-plugins-official) — needed for cart population and authentication
  ```
  /plugin install playwright@claude-plugins-official
  ```

## Permissions

Add the following to your project's `.claude/settings.json` so Claude can run the scripts and browser automation without prompting:

```json
{
  "permissions": {
    "allow": [
      "Bash(*prisma-*.sh*)",
      "mcp__plugin_playwright_playwright__browser_run_code",
      "mcp__plugin_playwright_playwright__browser_navigate",
      "mcp__plugin_playwright_playwright__browser_snapshot",
      "mcp__plugin_playwright_playwright__browser_click",
      "mcp__plugin_playwright_playwright__browser_type",
      "mcp__plugin_playwright_playwright__browser_fill_form",
      "mcp__plugin_playwright_playwright__browser_take_screenshot"
    ]
  }
}
```
