---
paths:
  - "projects/shop-frontend/app/**"
  - "worktrees/*/shop-frontend/app/**"
---

# Клиентский код shop-frontend

- Типы API — только из `app/api/model/`; `app/api/**` руками не правится, только `generate:api`.
- Zero `any`; без hardcode URL и ключей — только `runtimeConfig`.
- У каждого экрана с данными — loading, empty и error.
- `data-testid` на интерактивных элементах.
