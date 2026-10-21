#!/bin/sh
# Memento, UserPromptSubmit: реплика пользователя — на сервер. Сервер дописывает её в
# автоэпизод сессии (если он не выключен) и отвечает строкой момента значимости («запомни»,
# поправка, согласие, «важно») или пустым текстом; строка уходит агенту в контекст рядом с
# репликой. Событие — JSON на stdin — вкладывается в тело как есть: сервер берёт из него
# только session_id и prompt. Любой сбой — молча и код 0: реплика идёт агенту и без памяти.
# POSIX sh; на Windows — Git Bash.

[ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || exit 0
event=$(cat)
case $event in
*[![:space:]]*) ;;
*) exit 0 ;;
esac
. "$(dirname -- "$0")/lib.sh"

out=$(post /v1/hook/prompt "{\"project\":$(quote "$project"),\"event\":$event,\"store\":$store}" 2) ||
	exit 0
case $out in
*[![:space:]]*) printf '%s\n' "$out" ;;
esac
exit 0
