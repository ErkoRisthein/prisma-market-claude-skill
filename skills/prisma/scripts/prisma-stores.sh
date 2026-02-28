#!/usr/bin/env bash
# List all Prisma Market stores
# Usage: prisma-stores.sh

set -euo pipefail

PAYLOAD='{"query":"{ stores { id name } }"}'

RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST https://graphql-api.prismamarket.ee \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://www.prismamarket.ee' \
  -H 'Referer: https://www.prismamarket.ee/' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
  -d @-)

python3 -c "
import json, sys

data = json.loads(sys.argv[1])
stores = data.get('data', {}).get('stores', [])

if not stores:
    print('No stores found.')
    sys.exit(0)

results = [{'id': s['id'], 'name': s['name']} for s in stores]
print(json.dumps(results, indent=2, ensure_ascii=False))
" "$RESPONSE"
