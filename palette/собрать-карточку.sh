#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 -m pip install -q -r requirements.txt
if [[ -n "${1:-}" ]]; then
  python3 make_card.py "$1"
else
  python3 make_card.py
fi
echo "готово: $(pwd)/карточка.png"
