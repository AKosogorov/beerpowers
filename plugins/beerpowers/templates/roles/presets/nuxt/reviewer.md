# Пресет: Nuxt → reviewer

> Фрагменты для слотов `templates/roles/reviewer-agent.md`, когда фронтенд проекта — Nuxt.
> Строки про сгенерированный клиент API — только если он генерируется из схемы бэкенда.

## Слот `GATE_NOTES`

Если отдельного скрипта `typecheck` на фронте нет, типы проверяются внутри `build`
(`vue-tsc` через `typescript.typeCheck`): критерий — ноль строк `error TS` в полном логе
(код выхода — charter, «Число в отчёте…»), перед прогоном — `nuxt prepare`. В отчёте:
`typecheck: внутри build, 0 error TS`.

## Слот `STACK_CHECKLISTS`

### Frontend — Nuxt

```
[ ] Типы API только из сгенерированного клиента (app/api/model)
[ ] В app/api/** нет ручных правок — только перегенерация
[ ] Конфиг и ключи — только runtimeConfig
[ ] SSR не потерян: { server: false } только с обоснованием
```
