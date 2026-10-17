#!/usr/bin/env python3
"""Плейсхолдеры {{...}} в plugins/ должны входить в белый список из commands/setup.md.

Дополнительно ловит деформированные плейсхолдеры ({{ BUILD_CMD }}, {{build_cmd}}) и
несбалансированные скобки ({{BUILD_CMD} / {BUILD_CMD}}), которые строгий паттерн молча
пропустил бы. Литерал-иллюстрация `{{...}}` допустим.

Каждый слот шаблона (templates/**/*.md) описан: назван в commands/setup.md или имеет раздел
«## Слот `<ИМЯ>`» в пресете. Слот, о котором setup не знает, сборка оставляет в проекте
буквально — workspace-check это поймает, но уже у пользователя.

Обратная проверка examples/ (*.md и *.json — settings тоже генерируется):
это «сгенерированный» вид — плейсхолдеров там быть не должно вовсе.
"""
import pathlib
import re
import sys

ALLOWED = {
    # стек — подставляет setup Phase 1
    "FRONTEND_FRAMEWORK", "BACKEND", "DATABASE", "FILE_STORAGE", "DEV_CMD", "BUILD_CMD",
    "TYPECHECK_CMD", "TEST_RUNNER", "E2E_TOOL",
    # общие
    "PROJECT", "BEERPOWERS_VERSION",
    # charter — setup 4.1
    "PURPOSE", "STACK_TABLE", "COMMANDS", "ROLES_TABLE", "MODELS", "INTAKE_MODE",
    "PROJECT_RULES", "UNIVERSAL_SKILLS", "MEMORY_FILES_EXTRA",
    # team-lead — setup 4.1a
    "CLASS_EXTRA", "EFFORT_TABLE", "MODEL_EXTRA", "GATES_EXTRA", "CLOSING_EXTRA",
    # память — setup 4.5
    "OWNERS_EXTRA", "NEVER_CODE", "CONFIRM_EXTRA", "PROJECT_MAP", "BREAKPOINTS", "INVARIANTS_DETAILED",
    "COMMANDS_INDEX",
    # роли — setup 4.2, значения стековых слотов — templates/roles/presets/
    "ROLE_SKILLS", "ROLE_CONTEXT", "SKILLS_GUIDE", "DOES_NOT_TOUCH", "ROLE_SCOPE",
    "REPO_RULES", "STACK_CHECKLIST", "STACK_CHECKLISTS",
    "NATIVE_TOOLS_EXAMPLES", "HARD_RULES",
    "DESIGN_FIRST_QUESTION", "LAYER_CANON", "REVIEW_SMELLS", "CONSULT_TEST",
    "LAYER_INVARIANTS", "PROCESS_NOTES", "SCHEMA_CONVENTIONS", "MIGRATION_TEMPLATE", "QUERY_PLAN",
    "N_PLUS_ONE", "FRONTEND_CONFIG", "TEST_RUN", "DOMAIN_COVERAGE", "PIPELINE_FACTS",
    "SECURITY_CHECKLIST", "PERF_CHECKLIST", "ARCHITECTURE_NOTES", "PM_PIPELINE",
}

STRICT = re.compile(r"^\{\{([A-Z0-9_]+)\}\}$")
# {{FOO} (нет закрывающей пары) или {FOO}} (нет открывающей) — потерянная скобка в шаблоне.
UNBALANCED = re.compile(r"\{\{[A-Z0-9_]+\}(?!\})|(?<!\{)\{[A-Z0-9_]+\}\}")


def example_files():
    root = pathlib.Path("examples")
    return sorted(list(root.rglob("*.md")) + list(root.rglob("*.json")))


bad = []
for path in sorted(pathlib.Path("plugins").rglob("*.md")):
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r"\{\{[^{}]*\}\}", text):
        token = m.group(0)
        strict = STRICT.match(token)
        if strict:
            if strict.group(1) not in ALLOWED:
                bad.append(f"{path}: {token} — не из белого списка")
        elif re.search(r"[A-Za-z0-9]", token):
            bad.append(f"{path}: {token} — деформированный плейсхолдер (пробелы/регистр?)")
    for m in UNBALANCED.finditer(text):
        bad.append(f"{path}: {m.group(0)} — несбалансированные скобки плейсхолдера")

setup_text = pathlib.Path("plugins/beerpowers/commands/setup.md").read_text(encoding="utf-8")
presets = "".join(p.read_text(encoding="utf-8") for p in pathlib.Path("plugins/beerpowers/templates/roles/presets").rglob("*.md"))
for path in sorted(pathlib.Path("plugins/beerpowers/templates").rglob("*.md")):
    for name in sorted(set(re.findall(r"\{\{([A-Z0-9_]+)\}\}",path.read_text(encoding="utf-8")))):
        if name not in setup_text and f"## Слот `{name}`" not in presets:
            bad.append(f"{path}: {{{{{name}}}}} — слот не описан ни в setup.md, ни разделом «## Слот» пресета")

for path in example_files():
    text = path.read_text(encoding="utf-8")
    for m in re.finditer(r"\{\{[^{}]*\}\}", text):
        if re.search(r"[A-Za-z0-9]", m.group(0)):
            bad.append(f"{path}: {m.group(0)} — в examples/ плейсхолдеры должны быть подставлены")
    for m in UNBALANCED.finditer(text):
        bad.append(f"{path}: {m.group(0)} — в examples/ остаток битого плейсхолдера")

if bad:
    print("Проблемные плейсхолдеры (обнови белый список в setup.md и в этом скрипте — или шаблон):")
    print("\n".join(bad))
    sys.exit(1)

print(f"OK: плейсхолдеры plugins/ из белого списка ({len(ALLOWED)} имён), деформированных и несбалансированных нет, examples/ (*.md + *.json) без плейсхолдеров")
