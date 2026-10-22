// Подмена тестового раннера для mutants.test.sh.
//
//   node fake-mutant-test.mjs <тестовый файл>
//
// Тестовый файл — строки «expect <подстрока>»: каждая обязана стоять в src/rule.txt каталога
// запуска, иначе код 1. Без vendor/marker (ссылка mutate.link) или .env.testing (mutate.copy)
// — код 3: копия собрана не так. $FAKE_LITTER — оставить в каталоге неотслеживаемый файл.
// Каждый запуск дописывает в $REPORT/s<слот>.txt каталог и базу воркера.
import fs from 'node:fs';
import path from 'node:path';

const [testFile] = process.argv.slice(2);
if (process.env.REPORT) {
  fs.appendFileSync(path.join(process.env.REPORT, `s${process.env.BEERPOWERS_TEST_SLOT}.txt`), `copy=${process.cwd()} db=${process.env.DB_NAME ?? ''}\n`);
}
await new Promise((r) => setTimeout(r, Number(process.env.FAKE_SLEEP_MS ?? 0)));
if (process.env.FAKE_LITTER) fs.writeFileSync('junk.txt', 'litter\n');
if (!fs.existsSync('vendor/marker') || !fs.existsSync('.env.testing')) {
  console.log('копия без vendor/marker или .env.testing');
  process.exit(3);
}
// $FAKE_COMPOSER — код ищется так, как его ищет автозагрузчик composer: от реального пути
// vendor/composer два уровня вверх. $FAKE_SRC_DIR — код читается из чужого дерева: так выглядит
// тест, который не видит копию.
const srcDir = process.env.FAKE_SRC_DIR
  ?? (process.env.FAKE_COMPOSER ? path.resolve(fs.realpathSync('vendor/composer'), '..', '..') : '.');
const src = fs.readFileSync(path.join(srcDir, 'src/rule.txt'), 'utf8');
let bad = 0;
for (const line of fs.readFileSync(testFile, 'utf8').split('\n')) {
  const m = line.match(/^expect (.+)$/);
  if (m && !src.includes(m[1])) { console.log(`FAIL: нет «${m[1]}»`); bad++; }
}
console.log(bad ? `${bad} failed` : 'OK');
process.exit(bad ? 1 : 0);
