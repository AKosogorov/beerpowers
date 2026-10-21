// Подмена раннера тестов для parallel-tests.test.sh.
//
//   node fake-test-runner.mjs <junit> <файл>…        — split: тесты из названных файлов
//   node fake-test-runner.mjs <junit> --native <n>   — native: все файлы tests/ каталога запуска
//   node fake-test-runner.mjs --prepare              — подготовка слота: только запись в отчёт
//
// Файл теста — строка «cases=3 time=0.2 fail=1»: столько testcase, столько секунд сна на файл,
// столько упавших. Каждый запуск дописывает в $REPORT/<вид>-<слот>.txt, с какими переменными
// и аргументами его позвали.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const report = (kind, lines) => {
  if (!process.env.REPORT) return;
  const slot = process.env.BEERPOWERS_TEST_SLOT ?? 'all';
  fs.appendFileSync(path.join(process.env.REPORT, `${kind}-${slot}.txt`), lines.join('\n') + '\n');
};

if (args[0] === '--prepare') {
  report('prepare', [`slot=${process.env.BEERPOWERS_TEST_SLOT}`, `db=${process.env.DB_NAME ?? ''}`]);
  process.exit(Number(process.env.FAKE_PREPARE_CODE ?? 0));
}

const [junit, ...rest] = args;
let files = rest;
let n = '';
if (rest[0] === '--native') {
  n = rest[1];
  files = fs.readdirSync('tests').sort().map((f) => `tests/${f}`);
}

let xml = '';
let failed = 0;
let ms = 0;
for (const f of files) {
  const spec = Object.fromEntries(fs.readFileSync(f, 'utf8').trim().split(/\s+/).map((kv) => kv.split('=')));
  const cases = Number(spec.cases ?? 1);
  const t = Number(spec.time ?? 0.05);
  const fail = Number(spec.fail ?? 0);
  for (let k = 0; k < cases; k++) {
    const bad = k < fail;
    if (bad) failed++;
    xml += `<testcase name="t${k}" file="${path.resolve(f)}" classname="${path.basename(f)}" time="${(t / cases).toFixed(3)}">${bad ? '<failure>boom</failure>' : ''}</testcase>\n`;
  }
  ms += t * 1000;
}
report('run', [
  `slot=${process.env.BEERPOWERS_TEST_SLOT ?? ''}`,
  `slots=${process.env.BEERPOWERS_TEST_SLOTS ?? ''}`,
  `db=${process.env.DB_NAME ?? ''}`,
  `token=${process.env.TEST_TOKEN ?? ''}`,
  `n=${n}`,
  `files=${files.join(' ')}`,
]);
await new Promise((r) => setTimeout(r, ms));
fs.writeFileSync(junit, `<?xml version="1.0"?>\n<testsuites><testsuite name="fake">\n${xml}</testsuite></testsuites>\n`);
process.exit(failed ? 1 : 0);
