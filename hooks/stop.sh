#!/bin/sh
# Memento, Stop: конец хода агента — на сервер. Сервер обновляет автоэпизод сессии (итог
# агента, файлы, коммиты; если автоэпизод не выключен) и по сигналам хода решает, был ли
# момент значимости: решённая проблема — три упавшие команды за ход, затем успех, а
# memory_remember в ходе не было. Тогда его строка — блок хода с этой строкой (агент
# записывает урок); иначе — тишина. Событие — JSON на stdin — вкладывается в тело как есть:
# сервер берёт из него только session_id и last_assistant_message. Из транскрипта (JSONL
# Claude Code, разбор grep/sed) на сервер уходят только сигналы хода, пути правленых файлов
# и признак недоверенного текста — вывод команд (tool_result) не уходит. Любой сбой — молча и
# код 0. Сервер недоступен, а автоэпизод включён — тело ждёт в очереди досылки (flush.sh),
# один файл на сессию: новый ход заменяет прежний, как и на сервере. POSIX sh; на Windows —
# Git Bash.

[ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || exit 0
event=$(cat)
case $event in
*[![:space:]]*) ;;
*) exit 0 ;;
esac
# Claude Code уже продолжает ход после блока этого хука — не зацикливаться.
printf '%s\n' "$event" | grep -q '"stop_hook_active": *true' && exit 0
. "$(dirname -- "$0")/lib.sh"

# В строке JSON кавычка всегда экранирована, поэтому `"ключ":` и `{"ключ"`, `,"ключ"`
# бывают только в разметке, не внутри строк. Порядок ключей — как пишет Claude Code.
grab() {
	LC_ALL=C grep -a -o -E "$@"
}
USE='"type": *"tool_use", *"id": *"[^"]*", *"name": *'

# Путь Windows приходит в JSON с удвоенными обратными слэшами.
transcript=$(printf '%s\n' "$event" | grab '"transcript_path": *"(\\.|[^"\\])*"' |
	head -n 1 | sed 's/^"transcript_path": *"//; s/"$//; s/\\\(.\)/\1/g')
[ -n "$transcript" ] && [ -f "$transcript" ] || transcript=/dev/null

# Текущий ход — строки после последней реплики пользователя: строка user без tool_result
# и без isMeta (текст скилла посреди хода — не реплика).
start=$(LC_ALL=C grep -a -n '"role": *"user", *"content": *' "$transcript" |
	LC_ALL=C grep -a -v -e '[{,] *"tool_use_id": *"' -e '[{,] *"isMeta": *true' |
	tail -n 1 | sed 's/:.*//')
turn=$(sed -n "${start:-1},\$p" "$transcript")

# Команды хода (Bash, PowerShell) и их результаты по порядку: упавшие и успех последней.
ids=" $(printf '%s\n' "$turn" | grab "$USE\"(Bash|PowerShell)\"" |
	sed 's/.*"id": *"\([^"]*\)".*/\1/' | tr '\n' ' ')"
failed=0
last_ok=false
while read -r result; do
	[ -n "$result" ] || continue
	case $ids in
	*" ${result%:x} "*) ;;
	*) continue ;;
	esac
	case $result in
	*:x)
		failed=$((failed + 1))
		last_ok=false
		;;
	*) last_ok=true ;;
	esac
done <<EOF
$(printf '%s\n' "$turn" |
	grab '[{,] *("is_error": *(true|false) *, *)?"tool_use_id": *"[^"]*"( *, *"is_error": *(true|false))?' |
	sed -e '/"is_error": *true/s/.*"tool_use_id": *"\([^"]*\)".*/\1:x/' \
		-e 's/.*"tool_use_id": *"\([^"]*\)".*/\1/')
EOF
remembered=false
printf '%s\n' "$turn" | LC_ALL=C grep -a -q -E "$USE\"mcp__[^\"]*memento[^\"]*__memory_remember\"" &&
	remembered=true

# Сессия: недоверенный текст (веб, MCP не memento) и пути правленых файлов — строками JSON
# как есть, без повторов.
untrusted=false
grab "$USE\"[^\"]*\"" "$transcript" | sed 's/.*"name": *"//; s/"$//' |
	LC_ALL=C grep -a -v -E '^mcp__(plugin_memento_)?memento__' |
	LC_ALL=C grep -a -q -E '^(WebFetch|WebSearch|mcp__)' && untrusted=true
files=
while IFS= read -r path; do
	[ -n "$path" ] || continue
	case ",$files," in
	,,) files=$path ;;
	*",$path,"*) ;;
	*) files=$files,$path ;;
	esac
done <<EOF
$(grab '"name": *"(Edit|Write|NotebookEdit)", *"input": *\{("(\\.|[^"\\])*"|[^"{}])*\}' "$transcript" |
	grab '[{,] *"(file_path|notebook_path)": *"(\\.|[^"\\])*"' |
	sed 's/^[{,] *"[a-z_]*": *//')
EOF

# Коммиты с начала сессии (первая метка времени транскрипта): «хэш тема».
commits=
since=$(grab '"timestamp": *"[^"]*"' "$transcript" | head -n 1 | sed 's/.*: *"//; s/"$//')
if [ -n "$since" ]; then
	commits=$(git -C "$dir" log --since="$since" -n 50 --format='%h %s' 2>/dev/null |
		sed 's/[\\"]/\\&/g; s/[[:cntrl:]]/ /g; s/^/"/; s/$/"/' | tr '\n' ',' | sed 's/,$//')
fi

body="{\"project\":$(quote "$project"),\"event\":$event,\"store\":$store"
body="$body,\"files\":[$files],\"commits\":[$commits],\"failed\":$failed"
body="$body,\"last_ok\":$last_ok,\"remembered\":$remembered,\"untrusted\":$untrusted}"
sid=$(session)
if ! out=$(post /v1/hook/stop "$body" 4); then
	[ "$store" = true ] && [ -n "$sid" ] && enqueue "s-$sid" /v1/hook/stop "$body"
	exit 0
fi
# Итог хода дошёл — прежний итог сессии в очереди устарел: досланный позже, он заменил бы
# на сервере новый.
[ -z "$q" ] || [ -z "$sid" ] || rm -f "$q/s-$sid" 2>/dev/null
case $out in
*[![:space:]]*)
	printf '{"decision": "block", "reason": %s}\n' "$(quote "$out")"
	;;
esac
exit 0
