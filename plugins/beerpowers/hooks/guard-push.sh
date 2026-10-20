#!/bin/sh
# PreToolUse hook (Bash): не даёт отправить что-либо в защищённые ветки.
# Флаг barriers.guard-push в .claude/workspace.json, по умолчанию включён.
#
# Маски разрешений тут не помогают: они матчат префикс команды, а `git -C <путь> push …`
# под `Bash(git push:*)` не попадает вовсе. Поэтому решение принимается разбором команды.
#
# Блокируется: push в ветку по умолчанию, master или main, push без refspec (цель берётся
# из upstream и может оказаться защищённой), голый force, удаление ветки на сервере,
# --all/--mirror.
#
# Ветка по умолчанию — локальный refs/remotes/<remote>/HEAD, без запроса к серверу: хук
# ограничен по времени, а недоступный хостинг держал бы каждый push до таймаута. Поэтому
# master и main закрыты по имени всегда, даже если origin/HEAD устарел или не задан, —
# сервер защищает их и сам, барьер лишь страхует. Точную ветку по умолчанию с сервера
# считает .claude/bin/git-base.mjs.
#
# Плюс отдельный случай на GitLab (адрес remote содержит «gitlab») — первый push ветки
# задачи без -o merge_request.create. Это не защита ветки, а защита единственного момента,
# когда MR вообще можно завести push-опциями — на уже отправленной ветке они теряются молча.
#
# И push с силой, после которого из ветки на сервере пропадут коммиты, — отказ один раз
# со списком пропавших: решение, терять ли их, за человеком.

lib="$(dirname -- "$0")/lib/guard.sh"
[ -f "$lib" ] || exit 0
. "$lib"

input=$(cat)
# Ранний отсев по сырому событию — до чтения флага и разбора JSON: барьер срабатывает
# на каждой команде Bash, а каждый запуск sed на Windows стоит десятки миллисекунд.
case "$input" in
  *push*) ;;
  *) exit 0 ;;
esac

guard_gate guard-push on

cmd=$(guard_command "$input")

[ -z "$cmd" ] && exit 0

# Данные — не команды. Тело heredoc (сообщение коммита, тело MR) и содержимое кавычек
# могут упоминать любые формы push: они описывают их, а не выполняют.
cmd=$(guard_strip_data "$cmd")

case "$cmd" in
  *git*push*) ;;
  *) exit 0 ;;
esac


# Ветки, закрытые для push в репозитории $1 с remote $2.
protected_branches() {
  printf 'master\nmain\n'
  _pb_head=$(git -C "$1" symbolic-ref --quiet --short "refs/remotes/$2/HEAD" 2>/dev/null) \
    && printf '%s\n' "${_pb_head#"$2"/}"
  return 0
}

is_gitlab() {
  case "$(git -C "$1" remote get-url "$2" 2>/dev/null)" in
    *gitlab*) return 0 ;;
  esac
  return 1
}

deny() {
  guard_deny "$1"
}

LOST_STATE="$GUARD_ROOT/.claude/.cache/push-lost"

# Коммиты $2 (прежняя вершина), у которых в истории $3 (новая) нет пары: ни коммита с тем же
# патчем — git patch-id --stable переживает смену хеша при ребейзе и cherry-pick, — ни коммита
# с той же темой — она переживает правку патча на конфликте. Пара ищется среди коммитов новой
# истории после общего предка, поэтому влитое в основную ветку, на которую переложена ветка,
# пропажей не считается. Строка вывода — «<короткий хеш> <тема>».
lost_commits() {
  _lc_dir=$(mktemp -d 2>/dev/null) || return 0
  _lc_mb=$(git -C "$1" merge-base "$2" "$3" 2>/dev/null)
  git -C "$1" log --no-merges --no-color --no-ext-diff -p --format='commit %H' "$3" "^$_lc_mb" 2>/dev/null \
    | git patch-id --stable 2>/dev/null > "$_lc_dir/new-ids"
  git -C "$1" log --no-merges --format='%s' "$3" "^$_lc_mb" 2>/dev/null > "$_lc_dir/new-subjects"
  git -C "$1" log --no-merges --no-color --no-ext-diff -p --format='commit %H' "$2" "^$3" 2>/dev/null \
    | git patch-id --stable 2>/dev/null > "$_lc_dir/old-ids"
  git -C "$1" log --no-merges --format='%h%x09%H%x09%s' "$2" "^$3" 2>/dev/null > "$_lc_dir/old"
  awk -F '\t' '
    FILENAME == ARGV[1] { split($0, a, " "); newid[a[1]] = 1; next }
    FILENAME == ARGV[2] { newsubj[$0] = 1; next }
    FILENAME == ARGV[3] { split($0, a, " "); oldid[a[2]] = a[1]; next }
    (($2 in oldid) && (oldid[$2] in newid)) || ($3 in newsubj) { next }
    { print $1 " " $3 }
  ' "$_lc_dir/new-ids" "$_lc_dir/new-subjects" "$_lc_dir/old-ids" "$_lc_dir/old"
  rm -rf "$_lc_dir"
}

# Push с силой в $4 из refspec $3 не должен терять коммиты origin/$4 молча: стенд
# перезаливается ребейзом, выравнивается с --skip и пересобирается из веток, и в каждом
# из этих путей коммит может выпасть незаметно. Отказ — один раз на пару «прежняя вершина →
# новая»: пропажа бывает намеренной (задача снята, ветка схлопнута), и решает её человек.
check_lost() {
  _cl_src=${3%%:*}
  [ -n "$_cl_src" ] || return 0
  _cl_old=$(git -C "$1" rev-parse --verify --quiet "refs/remotes/$2/$4^{commit}" 2>/dev/null) || return 0
  _cl_new=$(git -C "$1" rev-parse --verify --quiet "$_cl_src^{commit}" 2>/dev/null) || return 0
  git -C "$1" merge-base --is-ancestor "$_cl_old" "$_cl_new" 2>/dev/null && return 0
  _cl_key="$_cl_old $_cl_new"
  [ -f "$LOST_STATE" ] && [ "$(cat "$LOST_STATE")" = "$_cl_key" ] && return 0

  if git -C "$1" merge-base "$_cl_old" "$_cl_new" >/dev/null 2>&1; then
    _cl_lost=$(lost_commits "$1" "$_cl_old" "$_cl_new")
    [ -z "$_cl_lost" ] && return 0
    _cl_count=$(printf '%s\n' "$_cl_lost" | wc -l | tr -d ' ')
    _cl_shown=$(printf '%s\n' "$_cl_lost" | head -n 30 | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n  /g')
    _cl_what="из $2/$4 пропадут коммиты ($_cl_count), которых в новой истории нет ни патчем, ни темой:\\n\\n  $_cl_shown"
  else
    _cl_what="у новой вершины нет общей истории с $2/$4 — push заменит ветку целиком."
  fi
  mkdir -p "$(dirname -- "$LOST_STATE")" 2>/dev/null
  printf '%s' "$_cl_key" > "$LOST_STATE"
  deny "После этого push $_cl_what\\nПокажи список человеку и назови причину по каждому: влит в основную ветку другой редакцией, задача снята, ветка схлопнута — или выпал по ошибке. Выпал — верни коммит (cherry-pick в дерево, откуда идёт push) и проверь снова: node .claude/bin/git-base.mjs --lost <дерево> $2/$4 HEAD. Пропажу подтвердил человек — повтори ту же команду: та же пара вершин второй раз не блокируется."
}

check_segment() {
  segment=$1

  case "$segment" in
    *push*) ;;
    *) return 0 ;;
  esac

  # `push` должен быть именно подкомандой git, а не частью другой команды: у `git stash push`
  # подкоманда — stash, и проверять его как отправку в удалённый репозиторий бессмысленно.
  # Слово git ищется явно, чтобы префиксы вроде `env FOO=bar git push …` не сбивали разбор.
  found_git=0
  subcommand=""
  skip_value=0
  take_repo=0
  repo="."

  for word in $segment; do
    if [ "$skip_value" = "1" ]; then
      skip_value=0
      continue
    fi

    if [ "$found_git" = "0" ]; then
      case "$word" in
        git|git.exe|*/git|*/git.exe) found_git=1 ;;
      esac
      continue
    fi

    if [ "$take_repo" = "1" ]; then
      repo=$word
      take_repo=0
      skip_value=0
      continue
    fi

    case "$word" in
      # Путь репозитория нужен ниже: по нему проверяется, отправлялась ли ветка раньше.
      # skip_value тут не ставится — значение забирает take_repo на следующем слове,
      # иначе путь съедается дважды и разбор уезжает на слово вперёд.
      -C)
        take_repo=1
        continue
        ;;
      # Опции самого git, несущие значение отдельным словом
      -c|--git-dir|--work-tree|--namespace|--exec-path)
        skip_value=1
        continue
        ;;
      -*)
        continue
        ;;
      *)
        subcommand=$word
        break
        ;;
    esac
  done

  [ "$found_git" = "1" ] || return 0
  [ "$subcommand" = "push" ] || return 0

  # Хвост после слова push; часть до него (git, -C, путь) роли не играет
  after=${segment#*push}

  skip_next=0
  positional=""
  mr_create=0
  take_option=0
  force=0

  for word in $after; do
    if [ "$skip_next" = "1" ]; then
      skip_next=0
      if [ "$take_option" = "1" ]; then
        take_option=0
        case "$word" in
          merge_request.create*) mr_create=1 ;;
        esac
      fi
      continue
    fi

    case "$word" in
      # push-опции несут значение отдельным словом: -o merge_request.target=<ветка> —
      # это целевая ветка MR, а не ветка отправки, в анализ попадать не должна.
      # Значение всё же осматривается: merge_request.create отличает первый push с заведением
      # MR от простой отправки ветки.
      -o|--push-option)
        skip_next=1
        take_option=1
        continue
        ;;
      --push-option=merge_request.create*)
        mr_create=1
        continue
        ;;
      --repo|--receive-pack|--exec)
        skip_next=1
        continue
        ;;
      --force|-f)
        deny "Голый --force перезаписывает удалённую ветку вслепую и затирает чужие коммиты, если кто-то успел отправить своё. Используй --force-with-lease: он откажется, если ветка изменилась с твоего последнего fetch."
        ;;
      # После rebase ветки задачи обычный push отклоняется — история переписана.
      # Флоу требует именно rebase, поэтому безопасная форма force разрешена;
      # цель при этом проверяется ниже наравне с остальными.
      --force-with-lease|--force-with-lease=*|--force-if-includes|--force-if-includes=*)
        force=1
        continue
        ;;
      --all|--mirror)
        deny "push --all и --mirror отправляют все ветки разом, включая защищённые. Отправляй ветку задачи поимённо."
        ;;
      --delete|-d)
        deny "Удаление ветки на сервере через push запрещено правилами проекта."
        ;;
      -*)
        continue
        ;;
      *)
        positional="$positional $word"
        ;;
    esac
  done

  # Первое позиционное слово — remote, второе — refspec
  remote=$(printf '%s' "$positional" | awk '{print $1}')
  refspec=$(printf '%s' "$positional" | awk '{print $2}')

  if [ -z "$remote" ] || [ -z "$refspec" ]; then
    deny "У push не указана ветка назначения — она возьмётся из upstream и может оказаться защищённой. Указывай явно: git push -u origin <ветка-задачи>."
  fi

  case "$refspec" in
    :*)
      deny "Удаление ветки на сервере через push запрещено правилами проекта."
      ;;
    +*)
      deny "Refspec с «+» — тот же голый --force: перезаписывает удалённую ветку вслепую. Убери «+» и используй --force-with-lease: он откажется, если ветка изменилась с твоего последнего fetch."
      ;;
  esac

  # Целевая ветка — часть после двоеточия, если refspec задан парой src:dst
  target=${refspec##*:}
  target_branch=${target#refs/heads/}

  for branch in $(protected_branches "$repo" "$remote"); do
    if [ "$target_branch" = "$branch" ]; then
      deny "Прямой push в $branch запрещён. Работа попадает туда только через merge request: отправь ветку задачи и открой MR."
    fi
  done

  # Дерево пересборки стенда (git-flow.md, «Залить ветку в стенд») отправляет только свой стенд.
  # Push из таких деревьев setup разрешает маской Bash(git -C worktrees/chore-*-rebuild/* push:*):
  # она снимает вопрос классификатора автоматического режима, но ветку назначения не ограничивает,
  # а имён стендов в настройках нет. Ветку ограничивает этот барьер — по имени каталога.
  case "$repo" in
    worktrees/chore-*-rebuild/*|*/worktrees/chore-*-rebuild/*)
      stand=${repo%%-rebuild/*}
      stand=${stand##*worktrees/chore-}
      if [ "$target_branch" != "$stand" ]; then
        deny "Из дерева пересборки стенда $stand push идёт только в ветку $stand, а не в $target_branch: git -C $repo push --force-with-lease origin $stand. Другую ветку отправляй из её собственного дерева или каталога репозитория."
      fi
      ;;
  esac

  # Релизные ветки здесь не запрещены: их перекладывает team-lead ребейзом, и без
  # --force-with-lease это невозможно. Голый --force отсекается выше и для них.
  #
  # Барьер тут заменён обязанностью: ребейз релизной переписывает базу всем веткам задач
  # от неё, и обычный rebase у них после этого даёт дубликаты. Кто перекладывает релизную,
  # тот сразу называет исполнителям новую голову и прежнюю базу для формы
  # `rebase --onto <новая голова> <прежняя база> <ветка>`.

  [ "$force" = "1" ] && check_lost "$repo" "$remote" "$refspec" "$target_branch"

  # Push-опции merge_request.* понимает только GitLab: на другом хостинге требовать их нечего.
  is_gitlab "$repo" "$remote" || return 0

  # Первый push ветки задачи — единственный момент, когда можно завести MR: push-опции
  # доходят до сервера только при реальной передаче ref, на уже отправленной ветке push
  # вернёт Everything up-to-date и опции потеряются. Ошибка молчит — push проходит успешно,
  # а MR не появляется, и второго шанса нет.
  # Ветка задачи — с кодом трекера в имени или с папкой задачи. Релизная, стенд и архив
  # заводятся без MR, и требовать его от них нельзя. Буквы перечислены явно: [A-Z] в части
  # локалей матчит и строчные.
  is_task=0
  case "$target_branch" in
    [ABCDEFGHIJKLMNOPQRSTUVWXYZ]*-[0-9]*) is_task=1 ;;
  esac
  [ -d "$GUARD_ROOT/memory/tasks/$target_branch" ] && is_task=1
  case "$is_task" in
    1)
      if [ "$mr_create" = "0" ]; then
        if ! git -C "$repo" rev-parse --verify --quiet "refs/remotes/$remote/$target_branch" >/dev/null 2>&1; then
          deny "Ветка $target_branch ещё не отправлялась, а push идёт без -o merge_request.create. Push-опции доходят до сервера только при реальной передаче ref: после этого push ветка станет отправленной, опции потеряются, и MR придётся заводить руками. Собери входы до отправки: (1) цель MR — node .claude/bin/git-base.mjs <репо> <КОД>; (2) assignee — владелец токена, ревьюеры — .claude/git-settings.local.json, репозитория там нет — спросить; (3) база актуальна — сверена с origin, ветка при отставании перенесена ребейзом; (4) текст описания: зачем, что сделано, чем проверено, что осталось непроверенным, правки вне объёма. Проверь токен для второго шага: GET /api/v4/user должен вернуть 200, иначе полное описание поставить будет нечем. Форма push и рецепт API — memory/commands/git.md, флоу — .claude/reference/git-flow.md. Проверка смотрит refs/remotes/$remote/$target_branch: ветка уже на сервере, а ссылки нет — сделай git -C <репо> fetch origin --prune, и проверка пропустит."
        fi
      fi
      ;;
  esac

  return 0
}

# Команда может быть составной: git add … && git push … ; каждый сегмент проверяется отдельно,
# иначе безопасный первый push прикрыл бы опасный второй
old_ifs=$IFS
IFS='
'
for segment in $(printf '%s' "$cmd" | tr ';&|' '\n\n\n'); do
  IFS=$old_ifs
  check_segment "$segment"
  IFS='
'
done
IFS=$old_ifs

exit 0
