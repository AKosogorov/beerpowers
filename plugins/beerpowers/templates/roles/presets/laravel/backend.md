# Пресет: Laravel → backend

> Фрагменты для слотов `templates/roles/backend-agent.md`, когда бэкенд проекта — Laravel
> с модульной раскладкой (`app/Application`, `app/Modules/<Модуль>`, `app/Infrastructure`)
> и PHPStan. setup вставляет раздел в слот с тем же именем; после вставки это проектный
> текст — сверь каталоги, список модулей, админку и уровень PHPStan с репозиторием.
> `<Namespace>` — корневой namespace проекта, `<уровень>` — уровень PHPStan из `phpstan.neon`.

## Слот `ROLE_SCOPE`

Код Laravel, кроме схемы БД:

- **`app/Application/`** — action-контроллеры API (`Controllers/Api/**/Action.php`),
  Request-валидация, Resources, Mappers, DTO ответов, Application Services.
- **`app/Modules/<Модуль>/`** — доменные сервисы, репозитории, модели Eloquent, DTO, Enums,
  Jobs, Mail, Observers, Commands. Список модулей — `memory/project/project-map.md`.
- **`app/Infrastructure/`** — интеграции за интерфейсом: S3, обработка изображений, Casts,
  Helpers, Exceptions, Providers.
- **Админка** (Orchid или аналог, если есть) — экраны и layouts, её файл маршрутов.
- **`routes/api.php`** — регистрация маршрутов.

## Слот `LAYER_INVARIANTS`

- **Границу модулей проверяй грепом**, не только `deptrac`: перед сдачей — поиск
  `use <Namespace>\Modules\` в изменённых файлах.
- **Валидация входа — FormRequest или Request-класс action'а.** Сырой `$request->all()`
  в сервис не уходит.
- **Секреты — только через `config()`/env.** Ни в коде, ни в логах, ни в коммитах.
- **Полные тайпхинты** параметров и возвращаемых значений в каждом новом файле.

## Слот `PROCESS_NOTES`

Слои шага 2: где Application Service, где сервис модуля, где Infrastructure. Публичный
контракт API шага 5 — swagger-аннотации (l5-swagger): у `front` клиент генерируется из этой
схемы.

## Слот `GATE_NOTES`

Сверь по `Makefile`, какие цели входят в агрегирующую `make check`: статанализ в неё может
не входить. Тогда гони `check` и `phpstan` как две отдельные цели — «check зелёный» ещё
не значит, что уровень PHPStan пройден.

## Слот `NATIVE_TOOLS_EXAMPLES`

FormRequest вместо ручной валидации, Eloquent-каст вместо преобразования в сервисе, очередь
Laravel вместо самописного диспетчера, Policy вместо россыпи проверок.

## Слот `STACK_CHECKLIST`

- [ ] Поиск осиротевшего после переноса или удаления кода — по `app`, `tests`, `database`,
      `resources`, `routes`
- [ ] `declare(strict_types=1);` и полные тайпхинты во всех новых файлах
- [ ] Контроллер зовёт Application Service, не доменный сервис
- [ ] Деньги — через каст денег проекта, нигде не float/decimal
- [ ] Вход валидируется Request-классом
- [ ] `phpstan` (уровень `<уровень>`) ✅ · `lint` ✅ · `deptrac` ✅ (либо `make check`
      целиком плюс отдельный `phpstan`)
- [ ] Изменился контракт API — swagger обновлён
