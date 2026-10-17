---
name: commands-figma
description: Фреймы макета Figma для задач shop — скрипт .claude/bin/figma-export
metadata:
  type: project
---

# Figma — фреймы макета

```bash
.claude/bin/figma-export '<ссылка на фрейм с node-id>' --save <КОД>
.claude/bin/figma-export '<ссылка>' --out memory/tasks/<КОД>/figma/<имя>.png
```

Фрейм ложится в `memory/tasks/<КОД>/figma/` (под gitignore); папка задачи должна уже существовать.
Доступ — шаблон `.claude/figma-settings.json.example`.
