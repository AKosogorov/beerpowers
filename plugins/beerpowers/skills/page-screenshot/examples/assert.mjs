// Проверки прогона form-save.json по JSONL от cdp-run.mjs — образец отдельного шага проверок:
// инструмент только прогоняет сценарии и пишет, что увидел, а что из этого верно, решает
// задача. Проверка называет ожидание и печатает фактическое значение, если оно другое.
//
// Запуск: node assert.mjs <результат.jsonl>
import { readFileSync } from 'node:fs'

const results = readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l))
let total = 0
let failed = 0
const check = (r, label, ok, actual) => {
  total++
  if (!ok) failed++
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${r.name}: ${label}${ok ? '' : `  факт=${JSON.stringify(actual)}`}`)
}
const requests = (r, method, path) => r.network.filter(n => n.method === method && new URL(n.url).pathname === path)

const CHECKS = {
  'save-blocked': (r) => {
    check(r, 'пара не заполнена — сообщение на пустой долготе', r.state.pairMessage === 'Заполните и широту, и долготу или очистите оба поля', r.state.pairMessage)
    check(r, 'заблокированное сохранение не шлёт POST', requests(r, 'POST', '/edit').length === 0, requests(r, 'POST', '/edit'))
    check(r, 'список офисов — из подмены mergePatch', r.state.source === 'mock' && r.state.offices.length === 3, r.state)
  },
  'save-ok': (r) => {
    const [post] = requests(r, 'POST', '/edit')
    // Статус — после редиректа: сохранение отвечает 302, страница после него — 200.
    check(r, 'POST /edit: 302, затем 200', post?.redirects.map(x => x.status).join() === '302' && post.status === 200, post)
    check(r, 'после сохранения — та же форма с флагом saved', new URL(r.state.url).search === '?saved=1', r.state.url)
    check(r, 'скриншот снят', r.screenshots.length === 1, r.screenshots)
  },
  'offices-empty': (r) => {
    check(r, 'подмена json заменила ответ целиком', r.state.source === 'mock-empty', r.state.source)
  },
}

for (const r of results) {
  check(r, 'сценарий прошёл', r.ok, r.error)
  if (!r.ok) continue
  const errors = r.console.filter(c => c.level === 'error' || c.level === 'exception')
  check(r, 'console без ошибок', errors.length === 0, errors)
  const bad = r.network.filter(n => n.status >= 400 || n.failed)
  check(r, 'сеть без ответов ≥ 400 и обрывов', bad.length === 0, bad)
  CHECKS[r.name.split('@')[0]]?.(r)
}
console.log(`TOTAL checks=${total} failed=${failed}`)
process.exit(failed ? 1 : 0)
