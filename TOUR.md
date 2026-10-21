# 🗺️ Экскурсия по плагину

Порядок чтения для человека, который хочет понять всю логику beerpowers — от общего замысла
к деталям. Каждая остановка опирается на предыдущие, поэтому порядок важнее полноты: можно
остановиться после любой остановки и уже понимать картину на этом уровне. В скобках —
объём в строках, чтобы планировать время. Всего около 7,5 тысячи строк; первые три остановки —
чуть больше двух тысяч, и их хватает, чтобы понимать устройство целиком.

## 🧭 1. Что это и как устроено

1. [README.md](README.md) (246) — что плагин делает и зачем, для какого проекта, какая
   структура каталогов нужна до setup и как идёт задача от трекера до MR.
2. [CLAUDE.md](CLAUDE.md) (89) — архитектура одним экраном: что живёт в плагине (движок),
   а что setup генерирует в проект; engine-блоки; три оси оркестрации и где каждая описана;
   инварианты, которые держит CI.
3. [plugins/beerpowers/reference/workspace.md](plugins/beerpowers/reference/workspace.md) (312) —
   контракт движка с проектом: ключи `workspace.json` и git-настроек, маркеры engine-блоков
   и правило копий.
   Всё остальное ссылается на эти имена, поэтому их стоит знать до команд и шаблонов.

## 📦 2. Что получает проект

Сначала результат, потом генератор: так генератор читается как объяснение уже виденного.

1. [examples/README.md](examples/README.md) — какой проект собран в эталоне и что он показывает.
2. [examples/laravel-nuxt/](examples/laravel-nuxt/) — собранная команда. По порядку:
   `CLAUDE.md` (импорт charter), `.claude/workspace.json`, `.claude/git-settings.json`,
   `.claude/team-charter.md`, `.claude/team-lead.md`, одна-две роли из `.claude/agents/`,
   `.claude/settings.json`, `memory/MEMORY.md`. Подробно читать не нужно — достаточно увидеть, какие файлы появляются
   и что в них проектное, а что движковое (текст между маркерами `beerpowers:engine`).
3. [plugins/beerpowers/commands/setup.md](plugins/beerpowers/commands/setup.md) (433) — как это
   собирается: разведка без вопросов, анкета Q0–Q9 темами — по вызову на тему, подтверждение
   плана, генерация по шагам 4.0–4.8, проверка. Git-вопросы — Q9, последней темой; профиль
   предлагает `lib/git.mjs detect`. Барьер `guard-user-files` на время setup — в Critical Rules.

## 👥 3. Как работает команда

Ядро плагина. Здесь решается, сколько ролей поднимать, в каком порядке и с какими проверками.

1. [plugins/beerpowers/commands/team-up.md](plugins/beerpowers/commands/team-up.md) (171) —
   модель оркестрации рантайма Agent Teams (team-lead — главная сессия, роли — `Agent`,
   продолжение — `SendMessage`) и Decision Matrix A/B/C/D: сколько координации нужно задаче.
2. [plugins/beerpowers/templates/charter/team-lead.md](plugins/beerpowers/templates/charter/team-lead.md)
   (268) — как team-lead ведёт задачу: класс задачи, effort и модель каждой роли, бриф роли,
   развилки с пользователем, что он даёт гейтам, закрытие задачи.
   Самый важный файл после charter.
3. [plugins/beerpowers/templates/charter/team-charter.md](plugins/beerpowers/templates/charter/team-charter.md)
   (369) — правила, которые получает каждая роль на каждом запросе: порядок гейтов и маршрут
   `NOT APPROVED`, язык отчёта, git только у team-lead, база диффа, правило находки, shell-вызовы,
   комментарии, артефакты файлами.
4. [plugins/beerpowers/reference/intake-protocol.md](plugins/beerpowers/reference/intake-protocol.md)
   (139) — вторая ось: риск и обратимость решают, нужна ли дизайн-фаза и подтверждение.
5. [plugins/beerpowers/reference/orchestration-patterns.md](plugins/beerpowers/reference/orchestration-patterns.md)
   (274) — третья ось: шесть форм работы на движке Workflow. Можно отложить — нужен, когда
   задача раскладывается на много однотипных единиц.

## 🔄 4. Жизненный цикл задачи

От постановки до уборки после мержа, в порядке, в котором это происходит.

1. [plugins/beerpowers/commands/task-start.md](plugins/beerpowers/commands/task-start.md) (249) —
   старт и возобновление: постановка, разбор, класс, артефакты, ветки, dry-run, передача команде.
2. [plugins/beerpowers/reference/tasks-layout.md](plugins/beerpowers/reference/tasks-layout.md)
   (130) — что лежит в папке задачи и чем файлы отличаются друг от друга.
3. [plugins/beerpowers/commands/team-lazy.md](plugins/beerpowers/commands/team-lazy.md) (29) —
   основной режим: роли поднимаются по требованию.
4. [plugins/beerpowers/reference/git-flow.md](plugins/beerpowers/reference/git-flow.md) (338) —
   всё о git в одном месте: профили репозиториев (`main-default`, `dev-default`, `custom`),
   база задачи, коммиты, push, MR, git-шаги закрытия, стенды, выпуск.
5. [plugins/beerpowers/reference/worktrees.md](plugins/beerpowers/reference/worktrees.md) (141) —
   параллельная работа над задачами в отдельных рабочих каталогах.
6. [plugins/beerpowers/commands/retro.md](plugins/beerpowers/commands/retro.md) (468) — после
   мержа: уроки эпика, дистилляция папок задач в память, уборка.
7. [plugins/beerpowers/commands/tracker.md](plugins/beerpowers/commands/tracker.md) (35) — запись
   в трекер по ходу задачи: задача и баг по шаблону, комментарии, связи, статусы.
8. [plugins/beerpowers/commands/worktrees-clear.md](plugins/beerpowers/commands/worktrees-clear.md)
   (189) и [team-down.md](plugins/beerpowers/commands/team-down.md) (37) — уборка рабочих
   каталогов и остановка ролей.

## 🎭 5. Роли

Шаблоны промптов ролей; setup подставляет в них стек проекта. Порядок — по ходу работы над
задачей: кто проектирует, кто пишет, кто проверяет.

1. [architect-agent.md](plugins/beerpowers/templates/roles/architect-agent.md) (174) — дизайн,
   ADR, план и его отступления.
2. [backend-agent.md](plugins/beerpowers/templates/roles/backend-agent.md) (111),
   [database-agent.md](plugins/beerpowers/templates/roles/database-agent.md) (131),
   [frontend-agent.md](plugins/beerpowers/templates/roles/frontend-agent.md) (110) — исполнители
   по слоям.
3. [testing-agent.md](plugins/beerpowers/templates/roles/testing-agent.md) (154) — тесты,
   мутационные пробы, скриншоты.
4. [reviewer-agent.md](plugins/beerpowers/templates/roles/reviewer-agent.md) (273) — гейты,
   чеклисты, два прохода ревью, вердикт. Самая длинная роль: на ней держится качество.
5. [devops-agent.md](plugins/beerpowers/templates/roles/devops-agent.md) (69) и
   [auditor-agent.md](plugins/beerpowers/templates/roles/auditor-agent.md) (192) — инфраструктура
   и аудит.
6. [plugins/beerpowers/templates/roles/presets/](plugins/beerpowers/templates/roles/presets/) —
   стековые чеклисты, которые setup вставляет в проектную часть роли. Читать по своему стеку.

## 🧠 6. Память проекта

1. [plugins/beerpowers/templates/memory/MEMORY.md](plugins/beerpowers/templates/memory/MEMORY.md)
   (125) — индекс памяти: виды знания, куда какая запись, владельцы правил, как писать запись.
2. Каталоги рядом — `project/` (карта, инварианты, запреты), `commands/` (формы команд проекта),
   `tests/`, `issues/`, `adr/`: заготовки, которые setup и `/beerpowers:onboard` наполняют.

## 🛡️ 7. Страховки: хуки и барьеры

Инструкции ролям механизмами не заменяются, а страхуются ими. Здесь — чем именно.

1. [plugins/beerpowers/hooks/hooks.json](plugins/beerpowers/hooks/hooks.json) — какие хуки
   на каких событиях.
2. [plugins/beerpowers/hooks/session-start.sh](plugins/beerpowers/hooks/session-start.sh) (46) —
   правила ответа человеку из [rules/](plugins/beerpowers/rules/reply_blocking_asks.md),
   анонс команды, детектор дрейфа версий.
3. [plugins/beerpowers/reference/hooks.md](plugins/beerpowers/reference/hooks.md) (215) — все
   барьеры `guard-*`: что ловят, как выключаются. Сами скрипты `hooks/guard-*.sh` — по желанию,
   в каждом шапка объясняет, зачем он.
4. [plugins/beerpowers/reference/runtime-compat.md](plugins/beerpowers/reference/runtime-compat.md)
   (199) — замеры рантайма, на которых всё это построено: что доходит до роли само, что
   делает `exit 2`, что приходит в хук.

## 🛠️ 8. Инструменты ролей: скрипты и скиллы

1. [plugins/beerpowers/templates/bin/](plugins/beerpowers/templates/bin/) — скрипты, которые
   копируются в `.claude/bin/` проекта. Шапка каждого — справка (`--help` печатает её же).
   Главные: `git-base.mjs` (база задачи, цель MR, команда диффа) и `lib/git.mjs` под ним,
   `worktree-add` и `workspace-clean` (рабочие деревья и уборка), `yandex-tracker`
   (постановка из трекера) и `yandex-tracker-write.mjs` (запись в трекер), `cdp-screenshot.mjs` (скриншоты страниц), `parallel-tests.mjs` (полный прогон тестов
   несколькими процессами с лимитом на машину), `mutants.mjs` (мутационные пробы в копиях дерева), `workspace-check.mjs` (проверка собранного).
2. [plugins/beerpowers/skills/](plugins/beerpowers/skills/) — скиллы плагина. Процессные —
   `brainstorm`, `grill`, `minimal-diff`, `debug-loop`, `prototype`; рабочие — `page-screenshot`,
   `economy`, `summarizing-mr-links`, `tracker-task`.

## 📝 9. PM-дорожка

Нужна, только если в проекте работает роль `product`.

1. [plugins/beerpowers/commands/feature.md](plugins/beerpowers/commands/feature.md) (180) —
   хотелка от идеи до плана реализации.
2. [plugins/beerpowers/reference/feature-pipeline.md](plugins/beerpowers/reference/feature-pipeline.md)
   (108) — контракты артефактов конвейера.
3. [product-agent.md](plugins/beerpowers/templates/roles/product-agent.md) (133) и
   [product-onboard.md](plugins/beerpowers/commands/product-onboard.md) (68).

## 🔧 10. Сопровождение собранной команды

1. [plugins/beerpowers/commands/update.md](plugins/beerpowers/commands/update.md) (90) и
   [reference/migrations.md](plugins/beerpowers/reference/migrations.md) (187) — как новая версия
   плагина переносится в уже собранный проект.
2. [plugins/beerpowers/commands/doctor.md](plugins/beerpowers/commands/doctor.md) (153) —
   диагностика: что сломано и как починить.
3. [onboard.md](plugins/beerpowers/commands/onboard.md) (67),
   [token-audit.md](plugins/beerpowers/commands/token-audit.md) (73),
   [decision-brief.md](plugins/beerpowers/commands/decision-brief.md) (100) — разовые команды:
   наполнить память, разобрать расход токенов, собрать материал для внешнего решения.
4. [plugins/beerpowers/workflows/](plugins/beerpowers/workflows/) — Workflow-скрипты: ансамбль
   ревьюеров, аудит модели доступа по сущностям и охота за плавающими тестами.

## ✅ 11. Как проверяется сам плагин

1. [.github/workflows/validate.yml](.github/workflows/validate.yml) — что проверяет CI на каждый
   push; скрипты проверок — `.github/scripts/`.
2. [plugins/beerpowers/tests/hooks/cases.txt](plugins/beerpowers/tests/hooks/cases.txt) — фикстуры
   барьеров: вход и ожидаемое решение, строка на случай;
   [tests/bin/git.test.sh](plugins/beerpowers/tests/bin/git.test.sh) — git-логика скриптов.
3. [CHANGELOG.md](CHANGELOG.md) — что менялось и требует ли проект `/beerpowers:update`;
   [ROADMAP.md](ROADMAP.md) — практики, отложенные до триггера.
