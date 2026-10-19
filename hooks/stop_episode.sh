#!/bin/sh
# Memento, Stop: в сессии была работа (коммит, PR или три правки файлов), а эпизод не
# записан, — один раз за сессию просит агента вызвать memory_episode. Событие — JSON на
# stdin; транскрипт — JSONL Claude Code, разбор — grep/sed по блокам tool_use. Всё
# непонятное — молчание и код 0, а не блок. POSIX sh; на Windows — Git Bash.

REASON='Memento: в этой сессии была работа, а эпизод не записан. Если задача завершена — вызови memory_episode (project — git remote проекта, intent — что хотели, outcome — ok/partial/failed, summary — чем кончилось, report — итог, problems — на чём споткнулись); узнал устойчивое (путь, решение, урок) — ещё memory_remember. Если задача не завершена или ждёт ответа пользователя — ничего не записывай. В обоих случаях не повторяй предыдущий ответ: закончи одной короткой строкой.'

event=$(cat)
field() {
	printf '%s\n' "$event" | sed -n "s/.*\"$1\": *\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

# Claude Code уже продолжает работу после блока этого хука — не зацикливаться.
printf '%s\n' "$event" | grep -q '"stop_hook_active": *true' && exit 0
session=$(field session_id)
case $session in
'' | *[!A-Za-z0-9_-]*) exit 0 ;;
esac
# Путь Windows приходит в JSON с удвоенными обратными слэшами.
transcript=$(field transcript_path | sed 's/\\\\/\\/g')
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
[ -n "$CLAUDE_PLUGIN_DATA" ] || exit 0
mark="$CLAUDE_PLUGIN_DATA/episode/$session"
[ -e "$mark" ] && exit 0

# Имена инструментов из блоков {"type":"tool_use","id":…,"name":…,"input":…}.
uses() {
	LC_ALL=C grep -a "\"type\": *\"tool_use\"[^{}]*\"name\": *\"$1\"" "$transcript"
}
names=$(uses '[^"]*' | LC_ALL=C grep -a -o '"type": *"tool_use"[^{}]*"name": *"[^"]*"' |
	sed 's/.*"name": *"//; s/"$//')
printf '%s\n' "$names" | grep -q 'memory_episode$' && exit 0
edits=$(printf '%s\n' "$names" | grep -c -x -E 'Edit|Write|NotebookEdit')
if [ "$edits" -ge 3 ] ||
	uses Bash | LC_ALL=C grep -a -o -E '"command": *"([^"\\]|\\.)*"' |
	LC_ALL=C grep -q -E 'git commit|gh pr (create|merge)'; then
	mkdir -p "$CLAUDE_PLUGIN_DATA/episode" && : >"$mark" || exit 0
	printf '{"decision": "block", "reason": "%s"}\n' "$REASON"
fi
exit 0
