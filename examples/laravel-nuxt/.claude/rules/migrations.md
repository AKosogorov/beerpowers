---
paths:
  - "projects/shop-backend/database/migrations/**"
  - "worktrees/*/shop-backend/database/migrations/**"
---

# Миграции shop-backend

- Анонимный класс; идемпотентность — повторный прогон не падает (`Schema::hasTable` и подобные).
- Индекс на каждый FK и на колонки фильтра и сортировки.
- FK к владельцу — `ON DELETE CASCADE`.
- Миграция меняет существующие данные — развилка пользователю до применения.
