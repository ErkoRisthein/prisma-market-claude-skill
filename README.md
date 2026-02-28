# Prisma Market

Shop for groceries at [Prisma Market](https://www.prismamarket.ee) via Claude Code.

## Install

```
/plugin marketplace add ErkoRisthein/prisma-market-claude-skill
/plugin install prisma-market
```

## Setup

Create a `.env` file in the plugin's skill directory with your preferences:

```env
PRISMA_STORE_ID=542860184          # default store (Kristiine Prisma)
PRISMA_AUTH_METHOD=smart-id        # smart-id | mobile-id | id-card
PRISMA_PERSONAL_CODE=<isikukood>   # required for authentication
PRISMA_PHONE=<phone>               # required only for mobile-id
```

To find the `.env` location after install, ask Claude: "set up Prisma config".

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
