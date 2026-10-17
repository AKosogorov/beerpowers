#!/usr/bin/env python3
"""Шаблоны и копируемые файлы плагина не несут проектного и держат контракт engine-блоков.

Контракт — plugins/beerpowers/reference/workspace.md:
  * в `templates/**`, `hooks/**` и четырёх копируемых reference нет литералов проекта, из
    которого плагин вырос (`teplomash`, коды задач), и дат вида ДД.ММ.ГГГГ — прецеденты живут
    в retro-log.md проекта, а не в шаблоне. Каталоги `projects/`, `worktrees/`, `memory/tasks/` —
    константы движка, литералом проекта они не считаются;
  * маркеры `<!-- beerpowers:engine <имя> [if=<ключ>:<значение>] -->` парные, не вложенные,
    имена уникальны в файле, ключ условия — из схемы workspace.json;
  * внутри engine-блока нет плейсхолдеров `{{…}}`: блок в проекте байт в байт равен шаблону,
    иначе update не сольёт его механически.
"""
import pathlib
import re
import sys

PLUGIN = pathlib.Path("plugins/beerpowers")
COPIED_REFERENCE = ["hooks.md", "tasks-layout.md", "worktrees.md", "git-flow.md"]
TEXT_SUFFIXES = {".md", ".sh", ".mjs", ".js", ".json", ".txt", ""}

FORBIDDEN = [
    (re.compile(r"teplomash", re.IGNORECASE), "литерал проекта-эталона"),
    (re.compile(r"\b\d{2}\.\d{2}\.20\d{2}\b"), "дата в шаблоне — прецедент место в retro-log.md"),
]

OPEN = re.compile(r"<!-- beerpowers:engine ([a-z0-9-]+)(?: if=([A-Za-z.]+):([A-Za-z0-9_.-]+))? -->")
CLOSE = re.compile(r"<!-- /beerpowers:engine -->")
ANY_MARKER = re.compile(r"<!-- /?beerpowers:engine")
CONDITION_KEYS = {"layout", "ui"}
PLACEHOLDER = re.compile(r"\{\{[A-Z0-9_]+\}\}")


def files():
    roots = [PLUGIN / "templates", PLUGIN / "hooks"]
    for root in roots:
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in TEXT_SUFFIXES and path.name != ".gitkeep":
                yield path
    for name in COPIED_REFERENCE:
        path = PLUGIN / "reference" / name
        if path.is_file():
            yield path


def check_markers(path, lines, bad):
    open_name = None
    open_line = 0
    names = set()
    for number, line in enumerate(lines, start=1):
        if not ANY_MARKER.search(line):
            if open_name and PLACEHOLDER.search(line):
                bad.append(f"{path}:{number}: плейсхолдер внутри engine-блока «{open_name}»")
            continue
        opened = OPEN.search(line)
        if opened:
            if open_name:
                bad.append(f"{path}:{number}: блок открыт внутри «{open_name}» (строка {open_line}) — вложенных блоков нет")
            name, key = opened.group(1), opened.group(2)
            if name in names:
                bad.append(f"{path}:{number}: имя блока «{name}» повторяется в файле")
            if key and key not in CONDITION_KEYS:
                bad.append(f"{path}:{number}: условие по неизвестному ключу «{key}»")
            names.add(name)
            open_name, open_line = name, number
        elif CLOSE.search(line):
            if not open_name:
                bad.append(f"{path}:{number}: закрывающий маркер без открывающего")
            open_name = None
        else:
            bad.append(f"{path}:{number}: деформированный маркер engine-блока")
    if open_name:
        bad.append(f"{path}:{open_line}: блок «{open_name}» не закрыт")


def main():
    bad = []
    seen = 0
    blocks = 0
    for path in files():
        seen += 1
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for number, line in enumerate(lines, start=1):
            for pattern, reason in FORBIDDEN:
                if pattern.search(line):
                    bad.append(f"{path}:{number}: {reason}")
        if path.suffix == ".md":
            blocks += len(OPEN.findall(text))
            check_markers(path, lines, bad)
    if seen == 0:
        bad.append("не найдено ни одного файла шаблонов — проверка деградировала бы молча")
    if blocks == 0:
        bad.append("не найдено ни одного engine-блока — стиль маркеров изменился или шаблоны пусты")
    if bad:
        print("Шаблоны нарушают контракт:")
        print("\n".join(f"  - {b}" for b in bad))
        return 1
    print(f"OK: {seen} файл(ов) шаблонов без литералов проекта, {blocks} engine-блок(ов) парные, без плейсхолдеров внутри")
    return 0


if __name__ == "__main__":
    sys.exit(main())
