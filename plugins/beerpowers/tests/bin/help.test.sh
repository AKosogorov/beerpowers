#!/bin/sh
# Каждый скрипт templates/bin отвечает на --help кодом 0 и непустым текстом — вне workspace,
# до чтения .claude/workspace.json: doctor и setup проверяют машину именно так, и скрипт,
# который принимает --help за свой аргумент, выглядит сломанным.
#
# Запуск: sh plugins/beerpowers/tests/bin/help.test.sh

here=$(cd -- "$(dirname -- "$0")" && pwd)
bin=$(cd -- "$here/../../templates/bin" && pwd)

tmp=$(mktemp -d 2>/dev/null) || tmp="${TMPDIR:-/tmp}/bp-help-$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT

total=0
failed=0
for f in "$bin"/*; do
  [ -f "$f" ] || continue
  total=$((total + 1))
  case "$(head -n 1 "$f")" in
    *node*) run=node ;;
    *bash*) run=bash ;;
    *) run=sh ;;
  esac
  out=$(cd "$tmp" && "$run" "$f" --help 2>&1)
  code=$?
  if [ "$code" = 0 ] && [ -n "$out" ]; then
    echo "pass  $(basename "$f")"
  else
    failed=$((failed + 1))
    echo "FAIL  $(basename "$f") — код $code"
    printf '%s\n' "$out" | head -n 3 | sed 's/^/      /'
  fi
done

echo
echo "$total случаев, упало $failed"
[ "$failed" = 0 ]
