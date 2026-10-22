#!/bin/sh
# Memento, UserPromptSubmit: реплика пользователя — на сервер. Сервер дописывает её в
# автоэпизод сессии (если он не выключен) и отвечает строкой момента значимости («запомни»,
# поправка, согласие, «важно») или пустым текстом; строка уходит агенту в контекст рядом с
# репликой. Событие — JSON на stdin — вкладывается в тело как есть: сервер берёт из него
# только session_id и prompt. Любой сбой — молча и код 0: реплика идёт агенту и без памяти.
# Сервер недоступен, а автоэпизод включён — реплика ждёт в очереди досылки (flush.sh);
# строка момента после обрыва уже ни к чему, поэтому при выключенном автоэпизоде очереди нет.
# POSIX sh; на Windows — Git Bash.

[ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || exit 0
event=$(cat)
case $event in
*[![:space:]]*) ;;
*) exit 0 ;;
esac
. "$(dirname -- "$0")/lib.sh"

body="{\"project\":$(quote "$project"),\"event\":$event,\"store\":$store}"
if ! out=$(post /v1/hook/prompt "$body" 2); then
	[ "$store" = true ] && enqueue "p-$(date +%s)-$$" /v1/hook/prompt "$body"
	exit 0
fi
case $out in
*[![:space:]]*) printf '%s\n' "$out" ;;
esac
exit 0
