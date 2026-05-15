#!/usr/bin/env bash
# List Prisma category tree for traversal.
# Usage:
#   prisma-categories.sh                 # top-level categories
#   prisma-categories.sh <parent-slug>   # direct children of the given category
#   prisma-categories.sh --tree          # full nested tree (top + 1 level)
# Examples:
#   prisma-categories.sh
#   prisma-categories.sh lapsed
#   prisma-categories.sh lapsed/mahkmed-ja-lapsehooldus
#
# Uses Store.navigation GraphQL field. Combine with prisma-category.sh to drill
# down: list categories → list items in a category → see item details.

set -euo pipefail

source "$(dirname "$0")/_env.sh"

PARENT_SLUG=""
TREE=false
case "${1:-}" in
  --tree) TREE=true ;;
  *) PARENT_SLUG="${1:-}" ;;
esac

STORE_ID="${PRISMA_STORE_ID:-542860184}"

QUERY='{ store(id: "'"$STORE_ID"'") { navigation { id slug name children { id slug name children { id slug name } } } } }'
PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$QUERY")

RESPONSE=$(printf '%s' "$PAYLOAD" | curl -s -X POST https://graphql-api.prismamarket.ee \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://www.prismamarket.ee' \
  -H 'Referer: https://www.prismamarket.ee/' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
  -d @-)

python3 -c "
import json, sys

data = json.loads(sys.argv[1])
errors = data.get('errors')
if errors:
    print(json.dumps({'errors': errors}, indent=2, ensure_ascii=False))
    sys.exit(1)

nav = data.get('data', {}).get('store', {}).get('navigation') or []
parent = sys.argv[2]
tree_mode = sys.argv[3] == 'true'

def fmt(node, include_kids=False):
    item = {'slug': node['slug'], 'name': node['name'],
            'url': 'https://www.prismamarket.ee/tooted/' + node['slug']}
    kids = node.get('children') or []
    if include_kids and kids:
        item['children'] = [fmt(k, False) for k in kids]
    item['childCount'] = len(kids)
    return item

if tree_mode:
    print(json.dumps({
        'count': len(nav),
        'categories': [fmt(n, include_kids=True) for n in nav],
    }, indent=2, ensure_ascii=False))
    sys.exit(0)

if not parent:
    print(json.dumps({
        'parent': '(root)',
        'count': len(nav),
        'children': [fmt(n) for n in nav],
    }, indent=2, ensure_ascii=False))
    sys.exit(0)

# Find the parent node by slug. The shipped tree is 3 deep (root → L1 → L2),
# so look at all levels.
def find(nodes, slug):
    for n in nodes:
        if n['slug'] == slug:
            return n
        kids = n.get('children') or []
        hit = find(kids, slug)
        if hit:
            return hit
    return None

target = find(nav, parent)
if not target:
    print(json.dumps({'error': 'Slug not found in navigation tree', 'slug': parent}, indent=2, ensure_ascii=False))
    sys.exit(1)

kids = target.get('children') or []
print(json.dumps({
    'parent': target['slug'],
    'parentName': target['name'],
    'count': len(kids),
    'children': [fmt(k) for k in kids],
}, indent=2, ensure_ascii=False))
" "$RESPONSE" "$PARENT_SLUG" "$TREE"
