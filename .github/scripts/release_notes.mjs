#!/usr/bin/env node
// Печатает текст релиза версии — раздел `## <версия> — <дата>` из CHANGELOG.md без заголовка.
// Зовёт workflow release.yml; раздела нет — выход 1, и релиз без описания не создаётся.
//
//   node .github/scripts/release_notes.mjs 2.14.0
import fs from 'node:fs'

const version = process.argv[2]
if (!version) {
  console.error('нужна версия: node .github/scripts/release_notes.mjs <версия>')
  process.exit(2)
}

const lines = fs.readFileSync('CHANGELOG.md', 'utf8').split(/\r?\n/)
const start = lines.findIndex((line) => line.startsWith(`## ${version} `))
if (start < 0) {
  console.error(`в CHANGELOG.md нет раздела «## ${version} — <дата>»`)
  process.exit(1)
}
let end = lines.findIndex((line, i) => i > start && line.startsWith('## '))
if (end < 0) end = lines.length

console.log(lines.slice(start + 1, end).join('\n').trim())
