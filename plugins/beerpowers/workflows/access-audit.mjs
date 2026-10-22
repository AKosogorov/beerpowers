// access-audit — fan-out аудита модели доступа по сущностям → карта видимости + щели на стыках.
// Запуск (только по opt-in пользователя!): Workflow({ scriptPath: '<каталог плагина beerpowers>/workflows/access-audit.mjs',
//   args: { entities: ['order', 'user', ...], focus?: 'что особенно проверить' } })
// Барьер перед синтезом оправдан: карта и щели на стыках требуют ВСЕХ находок разом.
// Итоговую карту оркестратор коммитит в memory/ сам (workflow-агенты эфемерны).

export const meta = {
  name: 'access-audit',
  description: 'Параллельный аудит модели доступа по сущностям, синтез карты видимости и щелей на стыках',
  whenToUse: 'Периодический security-аудит видимости данных или проверка после изменения модели доступа',
  phases: [
    { title: 'Аудит', detail: 'агент на сущность' },
    { title: 'Синтез', detail: 'карта видимости + щели' },
  ],
}

if (!args || !Array.isArray(args.entities) || args.entities.length === 0) {
  throw new Error('args.entities обязателен: список сущностей для аудита, например { entities: ["order", "user"] }')
}
const FOCUS = (args && args.focus) ? `Особый фокус: ${args.focus}.` : ''

const ACCESS_FINDINGS = {
  type: 'object', required: ['entity', 'findings'],
  properties: {
    entity: { type: 'string' },
    findings: { type: 'array', items: {
      type: 'object', required: ['summary', 'severity'],
      properties: {
        file: { type: 'string' }, line: { type: 'number' },
        summary: { type: 'string' }, severity: { enum: ['P0', 'P1', 'P2', 'P3'] },
        fix: { type: 'string' },
      } } },
  },
}
const VISIBILITY_MAP = {
  type: 'object', required: ['map', 'gaps'],
  properties: { map: { type: 'string' }, gaps: { type: 'array', items: { type: 'string' } } },
}

// Формулировки — без механизма конкретного стека: проверка доступа бывает гардом, политикой,
// middleware, декоратором контроллера или правилом на уровне базы (RLS) — агент находит, чем
// она сделана в этом проекте, по memory/ и коду. Модель агентов — модель сессии: аудит
// доступа — security, и понижать его нельзя (team-lead.md, «Модель роли»).
const found = (await parallel(args.entities.map(e => () =>
  agent(
    `Аудит модели доступа сущности «${e}». Найди, чем в этом проекте держится доступ (гард,
     политика, middleware, декоратор контроллера, правило на уровне базы), и проверь:
     есть ли проверка доступа на каждой операции чтения и записи; наследуют ли дочерние
     сущности права родителя или заводят своего владельца в обход общего правила; видны ли
     чужие данные — другого пользователя, организации, тенанта; есть ли обходные пути —
     маршрут или обработчик мимо проверки, фоновая задача, вебхук, клиент или ключ
     с повышенными правами без проверки. ${FOCUS}
     Сверься с memory/ (доменные инварианты, карта проекта) и .claude/team-charter.md.
     Read-only. Находки с file:line.`,
    { label: `audit: ${e}`, phase: 'Аудит', schema: ACCESS_FINDINGS })))).filter(Boolean)

log(`Аудит завершён: ${found.length}/${args.entities.length} сущностей, ${found.reduce((n, r) => n + r.findings.length, 0)} находок`)

const map = await agent(
  `Собери из находок ниже карту видимости по ролям и акторам — кто какую сущность читает
   и меняет — и перечисли щели на стыках: дочерние сущности, наследующие права родителя;
   пересечения правил доступа; обходные пути.
   Находки:\n${JSON.stringify(found)}`,
  { phase: 'Синтез', schema: VISIBILITY_MAP })

return { map: map && map.map, gaps: (map && map.gaps) || [], raw: found }
