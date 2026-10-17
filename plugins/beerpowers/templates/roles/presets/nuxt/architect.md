# Пресет: Nuxt → architect

> Фрагменты для слотов `templates/roles/architect-agent.md`, когда фронтенд проекта — Nuxt
> с Pinia. Строки про сгенерированный клиент API — только если клиент генерируется
> из схемы бэкенда (orval или аналог); каталог клиента сверь с репозиторием.

## Слот `LAYER_CANON`

   - Клиент → composables + stores Pinia, запросы через сгенерированный клиент API (`front`).

## Слот `REVIEW_SMELLS`

```
[ ] Fat composable на фронте — fetch + бизнес-логика + UI-стейт в одном (разбить)
```
