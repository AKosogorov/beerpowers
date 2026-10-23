// Учебный сайт для cdp-run.test.sh и примера скилла page-screenshot: вход, форма с парой полей,
// сохранение через POST → 302 → 200, список офисов из API, страница указателя и сети /lab.
// Слушает 127.0.0.1 на свободном порту и печатает его первой строкой: port=<n>.
//
// Запуск: node plugins/beerpowers/tests/bin/cdp-run-site.mjs
import http from 'node:http'

const page = (title, body) => `<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<style>
  body { font: 16px sans-serif; margin: 24px; }
  label { display: block; margin: 8px 0; }
  .toast { position: fixed; left: 0; right: 0; bottom: 0; padding: 24px; background: #333; color: #fff; }
  #hint { position: fixed; left: 0; right: 0; top: 0; bottom: 0; background: rgba(0, 0, 0, .3); }
</style></head><body>${body}</body></html>`

const LOGIN = page('Вход', `
<form method="post" action="/login">
  <label>Почта <input name="email" type="email"></label>
  <label>Пароль <input name="password" type="password"></label>
  <button type="submit">Войти</button>
</form>`)

// Подсказка перекрывает страницу первые 600 мс: клик по «Сохранить» обязан её дождаться.
const EDIT = saved => page('Офис', `
<div id="hint">Подсказка</div>
${saved ? '<div class="toast">Сохранено</div>' : ''}
<form id="office" method="post" action="/edit">
  <label>Город <input name="city" value="Казань"></label>
  <label>Широта <input name="latitude"></label>
  <label>Долгота <input name="longitude"></label>
  <button type="submit">Сохранить</button>
</form>
<h2>Офисы</h2>
<ul id="offices"></ul>
<script>
  setTimeout(() => document.getElementById('hint').remove(), 600)
  const lat = document.querySelector('[name=latitude]'), lon = document.querySelector('[name=longitude]')
  const PAIR = 'Заполните и широту, и долготу или очистите оба поля'
  const check = () => {
    const a = lat.value.trim(), b = lon.value.trim()
    lat.setCustomValidity(!a && b ? PAIR : '')
    lon.setCustomValidity(a && !b ? PAIR : '')
  }
  lat.addEventListener('input', check)
  lon.addEventListener('input', check)
  fetch('/api/offices').then(r => r.json()).then((data) => {
    const list = document.getElementById('offices')
    list.dataset.source = data.meta.source
    if (!data.offices.length) list.innerHTML = '<li class="empty">Офисов нет</li>'
    for (const o of data.offices) list.insertAdjacentHTML('beforeend', '<li class="office">' + o.city + '</li>')
    console.warn('offices: ' + data.offices.length)
  })
</script>`)

// Указатель и сеть: наведение, протяжка, клик по видимой кнопке и обрыв запроса на другой
// origin (localhost ↔ 127.0.0.1): с заголовком content-type такой запрос идёт с preflight.
const LAB = page('Лаборатория', `
<div id="hov" style="height: 40px">наведи</div>
<div id="pad" style="height: 400px; background: #eee; touch-action: none">протяни</div>
<button id="go">запрос</button><div id="r"></div>
<div style="height: 3000px"></div>
<script>
  const hov = document.getElementById('hov')
  hov.addEventListener('mouseenter', () => { hov.dataset.on = '1' })
  const pad = document.getElementById('pad')
  let y0 = null, y1 = null
  pad.addEventListener('pointerdown', (e) => { y0 = y1 = e.clientY; pad.dataset.type = e.pointerType })
  pad.addEventListener('pointermove', (e) => { if (y0 !== null) y1 = e.clientY })
  pad.addEventListener('pointerup', () => { pad.dataset.dy = String(Math.round(y1 - y0)); y0 = null })
  const other = location.hostname === 'localhost' ? '127.0.0.1' : 'localhost'
  let ctl = null
  document.getElementById('go').addEventListener('click', () => {
    if (ctl) ctl.abort()
    ctl = new AbortController()
    fetch('http://' + other + ':' + location.port + '/api/slow', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}', signal: ctl.signal })
      .then(r => r.text()).then((t) => { document.getElementById('r').textContent = t }).catch(() => {})
  })
</script>`)

const OFFICES ={ offices: [{ city: 'Казань' }, { city: 'Воронеж' }], meta: { source: 'server' } }

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1')
  const authed = /(^|;\s*)sid=1/.test(req.headers.cookie ?? '')
  const html = (code, body, headers = {}) => {
    res.writeHead(code, { 'content-type': 'text/html; charset=utf-8', ...headers })
    res.end(body)
  }
  const redirect = (to, headers = {}) => { res.writeHead(302, { location: to, ...headers }); res.end() }
  let body = ''
  req.on('data', (d) => { body += d })
  req.on('end', () => {
    if (url.pathname === '/login' && req.method === 'GET') return html(200, LOGIN)
    if (url.pathname === '/login' && req.method === 'POST') {
      const form = new URLSearchParams(body)
      if (form.get('email') === 'admin@localhost' && form.get('password') === 'password') {
        return redirect('/edit', { 'set-cookie': 'sid=1; Path=/; HttpOnly' })
      }
      return html(422, LOGIN)
    }
    if (url.pathname === '/favicon.ico') { res.writeHead(204); return res.end() }
    if (url.pathname === '/lab') return html(200, LAB)
    if (url.pathname === '/api/slow') {
      const cors = { 'access-control-allow-origin': req.headers.origin ?? '*', 'access-control-allow-headers': 'content-type' }
      return setTimeout(() => { res.writeHead(req.method === 'OPTIONS' ? 204 : 200, cors); res.end(req.method === 'OPTIONS' ? '' : 'done') }, 300)
    }
    if (!authed) return redirect('/login')
    if (url.pathname === '/edit' && req.method === 'GET') return html(200, EDIT(url.searchParams.has('saved')))
    if (url.pathname === '/edit' && req.method === 'POST') return redirect('/edit?saved=1')
    if (url.pathname === '/api/offices') {
      res.writeHead(200, { 'content-type': 'application/json' })
      return res.end(JSON.stringify(OFFICES))
    }
    html(404, page('Нет', 'нет такой страницы'))
  })
})

server.listen(0, '127.0.0.1', () => console.log(`port=${server.address().port}`))
