---
name: commands-git
description: Git workspace shop — то, чего нет в git-flow.md, git-settings.json и у сервера
metadata:
  type: project
---

# Git — факты этого workspace

Правила, формы ветки, push, MR и схлопывания — `.claude/reference/git-flow.md`; профили
репозиториев — `.claude/git-settings.json`; ветки — у сервера (`node .claude/bin/git-base.mjs`).

## Токен API для MR

Оба репозитория ходят на GitLab по HTTPS: токен API отдаёт git credential helper
(`git-flow.md`, «Токен API»).
