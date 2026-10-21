#!/usr/bin/env python3
"""Имена engine-блоков в реестре миграций существуют в шаблонах.

`/beerpowers:update` ведёт слияние по записям `reference/migrations.md`: запись «блок `X`
в `team-lead.md`» он ищет в шаблоне и в проекте. Имя, которого в шаблоне нет, или имя
соседнего блока превращают ожидаемую разницу в «правку руками» — конфликт по таблице слияния.

Проверка: каждое имя, которое в реестре стоит в обратных кавычках сразу после слова «блок»
(«блок `a`», «engine-блок `a`», «в блоке `a` и `b`»), — имя engine-блока в каком-нибудь
шаблоне `templates/**`. Если в той же строке назван файл шаблона (`team-lead.md`,
`MEMORY.md`, роль) или строка говорит о charter, блок обязан быть именно в этом файле.

Что запись под текущую версию называет каждый изменённый блок, проверяет
`check_migrations.py`: ему нужен дифф с базой.
"""
import pathlib
import re
import sys

PLUGIN = pathlib.Path("plugins/beerpowers")
MIGRATIONS = PLUGIN / "reference" / "migrations.md"
TEMPLATES = PLUGIN / "templates"

OPEN = re.compile(r"<!-- beerpowers:engine ([a-z0-9-]+)(?: [^>]*)? -->")
ENTRY = re.compile(r"^## → (\S+)")
# «блок `a`», «блоке `a`», «блоки `a`, `b` и `c`», «engine-блок `a`».
MENTION = re.compile(r"блок[а-я]*\s+(`[a-z0-9-]+`(?:(?:,\s*|\s+и\s+)`[a-z0-9-]+`)*)")
NAME = re.compile(r"`([a-z0-9-]+)`")
FILE = re.compile(r"`([^`\s]*?([A-Za-z0-9_.-]+\.md))`")
CHARTER = re.compile(r"\bcharter\b")


def blocks_by_file():
    result = {}
    for path in sorted(TEMPLATES.rglob("*.md")):
        names = set(OPEN.findall(path.read_text(encoding="utf-8")))
        if names:
            result[path] = names
    return result


def files_named(line, by_file):
    """Шаблоны, которые строка называет: по имени файла в кавычках или словом charter."""
    named = set()
    for _, base in FILE.findall(line):
        named.update(p for p in by_file if p.name == base)
    if CHARTER.search(line):
        named.update(p for p in by_file if p.name == "team-charter.md")
    return named


def main():
    by_file = blocks_by_file()
    everywhere = set().union(*by_file.values())
    problems, checked = [], 0
    version = None
    for number, line in enumerate(MIGRATIONS.read_text(encoding="utf-8").splitlines(), start=1):
        entry = ENTRY.match(line)
        if entry:
            version = entry.group(1)
            continue
        named = files_named(line, by_file)
        for mention in MENTION.findall(line):
            for name in NAME.findall(mention):
                checked += 1
                where = f"{MIGRATIONS}:{number} (→ {version})"
                if name not in everywhere:
                    problems.append(f"{where}: блока `{name}` нет ни в одном шаблоне")
                elif named and not any(name in by_file[p] for p in named):
                    files = ", ".join(sorted(str(p) for p in named))
                    problems.append(f"{where}: блока `{name}` нет в {files}")
    if problems:
        print("Реестр миграций называет блоки, которых нет в шаблонах:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"OK: {checked} упоминаний engine-блоков в реестре миграций есть в шаблонах")
    return 0


if __name__ == "__main__":
    sys.exit(main())
