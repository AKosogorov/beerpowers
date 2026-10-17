---
name: summarizing-mr-links
description: Use when one or more merge requests or pull requests have just been created and the reply to the user is about to end
user-invocable: false
---

# Сводка ссылок после MR

Ответ, в котором заведены MR или PR, заканчивается сводкой ссылок — перед блоком
«Нужно от тебя», если он есть. Сводка состоит ровно из двух частей, подряд:

1. **Таблица markdown** — для перехода по клику.
2. **Та же таблица в блоке кода без тега** — для копирования одним нажатием в трекер или чат.

Строки таблицы, по порядку: задача в трекере, затем по строке на каждый MR с именем
репозитория в первой колонке.

## Образец

| Что | Ссылка |
|---|---|
| Задача | https://tracker.example/PROJ-123 |
| project-backend | https://gitlab.example/group/project-backend/-/merge_requests/77 |
| project-frontend | https://gitlab.example/group/project-frontend/-/merge_requests/41 |

    | Что | Ссылка |
    |---|---|
    | Задача | https://tracker.example/PROJ-123 |
    | project-backend | https://gitlab.example/group/project-backend/-/merge_requests/77 |
    | project-frontend | https://gitlab.example/group/project-frontend/-/merge_requests/41 |

## Условия

| Ситуация | Что делать |
|---|---|
| MR один | сводка всё равно: задача плюс одна строка |
| MR создан по ходу ответа, а не в конце | ссылку назвать сразу, а в конце — сводка со всеми |
| задачи в трекере нет | первая строка — репозиторий, строки задачи нет |
| блок кода | без тега языка: блок с тегом оболочки получает кнопку запуска, а это не команда |

Одна форма другую не заменяет: в блоке кода ссылки не кликаются, а таблицу вне блока
приходится выделять мышью по строкам.
