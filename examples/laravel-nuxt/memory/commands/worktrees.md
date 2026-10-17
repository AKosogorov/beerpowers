---
name: commands-worktrees
description: Worktree задач shop — заведение, порты, зависимости, тестовая база
metadata:
  type: project
---

# Worktree — проектные подробности

Правила и раскладка `worktrees/<КОД>/<репо>/` — `.claude/reference/worktrees.md`.

## Заведение

```bash
.claude/bin/worktree-add shop-backend <КОД>
.claude/bin/worktree-add shop-frontend <КОД>
```

Каталог — `worktrees/<КОД>/<имя-репо>/`, под gitignore корня.

## Зависимости и тестовая база

Проектного `.claude/bin/worktree-setup` нет: `vendor/` и `node_modules/` в новом worktree
ставятся руками (`composer install`, `npm ci`), а PHPUnit в worktree бэкенда ходит в ту же
базу `shop_test`, что и основной каталог, — два прогона одновременно мешают друг другу.
Понадобится параллельная работа в `shop-backend` — завести `worktree-setup` со своей тестовой
базой на worktree и `worktree-teardown` для её удаления.

