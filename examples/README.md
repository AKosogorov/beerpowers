# Examples — golden-референс генератора

Эталонный вывод `/beerpowers:setup` 2.0 для вымышленного проекта, собранный прогоном
`setup.md` по тексту на чистой фикстуре, без истории реального проекта; исходники приложения
в эталон не копировались.

| Каталог | Проект | Git | Что показывает |
|---|---|---|---|
| `laravel-nuxt/` | **shop** — Laravel 12 + Nuxt 4, бэк и фронт отдельными репозиториями | два репозитория в `projects/`, GitLab, оба на профиле `main-default` | Developer, состав Extended (`architect`, `backend`, `db`, `front`, `tester`, `reviewer`, `devops`, `auditor`, `explorer`), пресеты laravel / nuxt / postgres / gitlab, барьеры по дефолту, `quality-reminder` |

Эталон один: каждый пример сверяется с шаблонами при каждой их правке, и второй удваивал эту
работу. Роль `product`, профили `dev-default` и `custom` и GitHub в эталоне не представлены —
их правки сверяются по шаблонам, `check_templates.py` и `tests/bin/git.test.sh`.

В эталоне: `.claude/team-charter.md` и `.claude/team-lead.md`, роли `.claude/agents/`,
`.claude/workspace.json`, `settings.json`, `quality-gates.txt`, правила `.claude/rules/`, копии
`.claude/reference/`, память `memory/` по виду знания, `CLAUDE.md` с импортом charter и
`.gitignore`. Копии `.claude/bin/` и `.claude/hooks/` в эталон не входят: они побайтно равны
шаблонам плагина с подставленной версией, и CI сверяет это на фикстурах setup, а не здесь.

Назначение:

1. **Живая документация** — что именно появится в проекте после `/beerpowers:setup`.
2. **Golden-тест генератора** — правишь шаблоны `templates/` или структуру charter в setup 4.1 →
   обнови эталон (engine-блоки — механикой `update`, проектные части — руками) и сверь дифф:
   неожиданные изменения = регрессия генерации. CI: `check_placeholders.py` — не осталось
   плейсхолдеров `{{...}}`; `check_golden.py` — секции и штамп charter, `team-lead.md`
   и `workspace.json` рядом, поля frontmatter ролей, `agent-memory/<role>/MEMORY.md`, строка
   `## adversary:` в схеме отчёта `reviewer`, **каждый engine-блок побайтно равен шаблону**,
   копии reference равны файлам плагина.

Это НЕ рабочий проект: кода нет, пути и значения вымышленные.
