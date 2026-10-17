#!/usr/bin/env python3
"""Относительные markdown-ссылки в plugins/ указывают на существующие файлы."""
import pathlib
import re
import sys

# Файлы, которых в шаблоне нет, потому что setup создаёт их скриптом в проекте:
# индекс долга пишет `.claude/bin/tech-debt-index.mjs`.
GENERATED = {pathlib.Path("plugins/beerpowers/templates/memory/tech-debt/tech-debt.md")}

bad = []
for path in sorted(pathlib.Path("plugins").rglob("*.md")):
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r"\]\(([^)\s]+)\)", text):
        target = m.group(1)
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        rel = target.split("#")[0]
        if not rel:
            continue
        resolved = path.parent / rel
        if not resolved.exists() and pathlib.Path(*resolved.parts) not in GENERATED:
            bad.append(f"{path}: {target}")

if bad:
    print("Битые относительные ссылки:")
    print("\n".join(bad))
    sys.exit(1)

print("OK: относительные ссылки в plugins/ целы")
