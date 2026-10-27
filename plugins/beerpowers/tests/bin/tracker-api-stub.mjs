// Заглушка API Трекера для yandex-tracker-write.test.sh: держит задачи, связи и вложения
// в памяти, пишет каждый запрос строкой в журнал и ведёт себя как живой Трекер там, где это
// проверяется: связь «связана» на каждый ключ из описания, одна связь на пару задач, версия
// задачи растёт с каждым вложением, правка со старой версией получает 409. Комментарий
// с текстом «чужой» записывается от другого автора — так проверяется отказ по чужому.
//
// Запуск: node tracker-api-stub.mjs <файл порта> <журнал>

import fs from 'node:fs';
import http from 'node:http';

const [portFile, logFile] = process.argv.slice(2);
const issues = new Map();
const links = [];
// Счётчики раздельные, как у Трекера: id вложения не зависит от числа связей и комментариев.
const seq = {};
const nextId = (kind) => String((seq[kind] = (seq[kind] || 0) + 1));

const send = (res, code, body) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(body === undefined ? '' : JSON.stringify(body)); };

function view(key, l) {
  const fromSide = l.from === key;
  const other = fromSide ? l.to : l.from;
  const map = { 'depends on': ['depends', 'outward', 'inward'], 'is dependent by': ['depends', 'inward', 'outward'], relates: ['relates', 'outward', 'inward'], 'is subtask for': ['subtask', 'inward', 'outward'], 'is parent task for': ['subtask', 'outward', 'inward'] }[l.rel];
  return { id: l.id, type: { id: map[0] }, direction: fromSide ? map[1] : map[2], object: { key: other, display: issues.get(other)?.summary } };
}

http.createServer((req, res) => {
  let chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const raw = Buffer.concat(chunks);
    const url = new URL(req.url, 'http://x');
    const p = url.pathname.replace(/^\/v2/, '');
    const isJson = (req.headers['content-type'] || '').startsWith('application/json');
    const body = isJson && raw.length ? JSON.parse(raw.toString()) : null;
    fs.appendFileSync(logFile, `${req.method} ${p}${url.search} ${isJson ? JSON.stringify(body) : `<${raw.length} байт>`}\n`);
    let m;
    const known = /^\/issues\/([^/]+)\/(attachments|comments|transitions)/.exec(p);
    if (known && !issues.has(known[1])) return send(res, 404, { errorMessages: ['нет задачи'] });
    if (p === '/myself') return send(res, 200, { uid: 11, login: 'stub', display: 'Заглушка' });
    if (req.method === 'POST' && p === '/attachments') return send(res, 201, { id: nextId('att'), name: 'f' });
    if (req.method === 'POST' && p === '/issues') {
      const key = `${body.queue}-${issues.size + 1}`;
      issues.set(key, { ...body, key, version: 1, attachments: [], comments: [], status: { key: 'backlog', display: 'Беклог' }, type: { key: body.type, display: body.type }, queue: { key: body.queue } });
      // Как живой Трекер: каждому ключу из описания — связь «связана».
      for (const k of new Set(String(body.description).match(/\b[A-Z][A-Z0-9]+-\d+\b/g) || [])) links.push({ id: nextId('link'), from: key, to: k, rel: 'relates' });
      return send(res, 201, issues.get(key));
    }
    if ((m = /^\/issues\/([^/]+)$/.exec(p))) {
      const it = issues.get(m[1]);
      if (!it) return send(res, 404, { errorMessages: ['нет задачи'] });
      if (req.method === 'GET') return send(res, 200, it);
      if (req.method === 'PATCH') {
        if (Number(url.searchParams.get('version')) !== it.version) return send(res, 409, { errorMessages: ['Задача: не удалось сохранить изменения, попробуйте ещё раз.'] });
        Object.assign(it, body, { version: it.version + 1 });
        return send(res, 200, it);
      }
    }
    if ((m = /^\/issues\/([^/]+)\/attachments$/.exec(p))) {
      const it = issues.get(m[1]);
      if (req.method === 'GET') return send(res, 200, it.attachments);
      const a = { id: nextId('att'), name: 'f' };
      it.attachments.push(a);
      it.version++;
      return send(res, 201, a);
    }
    if ((m = /^\/issues\/([^/]+)\/attachments\/([^/]+)$/.exec(p)) && req.method === 'DELETE') {
      const it = issues.get(m[1]);
      it.attachments = it.attachments.filter((a) => a.id !== m[2]);
      return send(res, 204);
    }
    if ((m = /^\/issues\/([^/]+)\/comments$/.exec(p))) {
      const it = issues.get(m[1]);
      if (req.method === 'GET') return send(res, 200, it.comments);
      const createdBy = /чужой/.test(body.text) ? { id: '22', display: 'Другой' } : { id: '11', display: 'Заглушка' };
      const c = { id: Number(nextId('comment')), text: body.text, createdBy };
      it.comments.push(c);
      return send(res, 201, c);
    }
    if ((m = /^\/issues\/([^/]+)\/comments\/([^/]+)$/.exec(p))) {
      const it = issues.get(m[1]);
      const c = it.comments.find((x) => String(x.id) === m[2]);
      if (!c) return send(res, 404, { errorMessages: ['нет комментария'] });
      if (req.method === 'GET') return send(res, 200, c);
      if (req.method === 'PATCH') { c.text = body.text; return send(res, 200, c); }
      if (req.method === 'DELETE') { it.comments = it.comments.filter((x) => x !== c); return send(res, 204); }
    }
    if ((m = /^\/issues\/([^/]+)\/links$/.exec(p))) {
      const key = m[1];
      if (req.method === 'GET') return send(res, 200, links.filter((l) => l.from === key || l.to === key).map((l) => view(key, l)));
      // Одна связь на пару: новая заменяет прежнюю с тем же id.
      const old = links.find((l) => (l.from === key && l.to === body.issue) || (l.to === key && l.from === body.issue));
      if (old) Object.assign(old, { from: key, to: body.issue, rel: body.relationship });
      else links.push({ id: nextId('link'), from: key, to: body.issue, rel: body.relationship });
      return send(res, 201, {});
    }
    if ((m = /^\/issues\/([^/]+)\/links\/([^/]+)$/.exec(p)) && req.method === 'DELETE') {
      const i = links.findIndex((l) => l.id === m[2]);
      if (i >= 0) links.splice(i, 1);
      return send(res, 204);
    }
    if ((m = /^\/issues\/([^/]+)\/transitions$/.exec(p))) return send(res, 200, [{ id: 'close', to: { display: 'Закрыт' } }]);
    if ((m = /^\/issues\/([^/]+)\/transitions\/close\/_execute$/.exec(p))) {
      if (!body.resolution) return send(res, 422, { errorMessages: ['Вы должны указать значения для полей Резолюция.'] });
      const it = issues.get(m[1]);
      it.status = { key: 'closed', display: 'Закрыт' };
      it.resolution = { display: body.resolution };
      return send(res, 200, []);
    }
    if ((m = /^\/queues\/([^/]+)$/.exec(p))) return send(res, 200, { issueTypesConfig: [{ issueType: { key: 'task' }, resolutions: [{ key: 'fixed' }, { key: 'wontFix' }] }] });
    send(res, 404, { errorMessages: [`заглушка не знает ${req.method} ${p}`] });
  });
}).listen(0, '127.0.0.1', function () {
  fs.writeFileSync(portFile, String(this.address().port));
});
