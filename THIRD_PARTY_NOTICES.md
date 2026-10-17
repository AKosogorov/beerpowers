# Third-party notices

## toiiia/qtim-agent-team

<https://github.com/toiiia/qtim-agent-team>

Плагин `beerpowers` — форк плагина `qtim` 1.14.0 (коммит `4f51e09`): движок команды, команды,
reference, скилы, Workflow-скрипты, CI и golden-эталон унаследованы и переработаны. Copyright
и permission notice апстрима — в [`LICENSE`](LICENSE), первая строка copyright.

## Скилы, адаптированные апстримом

Часть скилов, унаследованных от qtim, — производные адаптации сторонних скилов под контракт
команды и русский язык: структура и часть правил заимствованы, текст написан заново, механики,
конфликтующие с ролевой моделью, не перенесены. Оригиналы распространяются по MIT; ниже —
их copyright и permission notice.

## mattpocock/skills

<https://github.com/mattpocock/skills>

Производные: `plugins/beerpowers/skills/debug-loop/` (из `diagnosing-bugs`),
`plugins/beerpowers/skills/prototype/` (из `prototype`),
`plugins/beerpowers/skills/grill/` (из `grilling` / `grill-me`).

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## DietrichGebert/ponytail

<https://github.com/DietrichGebert/ponytail>

Производное: `plugins/beerpowers/skills/minimal-diff/` (из `ponytail`).

```
MIT License

Copyright (c) 2026 DietrichGebert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Добавляя новый скил-адаптацию, впиши сюда апстрим и его notice — строки атрибуции
в шапке `SKILL.md` для этого недостаточно.
