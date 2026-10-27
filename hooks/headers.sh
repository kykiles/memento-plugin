#!/bin/sh
# Memento, помощник заголовков MCP-сервера плагина (headersHelper в .mcp.json; плагин 0.4.0):
# токен входа по ссылке с кодом (файл ~/.config/memento/token, его кладёт login.sh) —
# заголовком {"Authorization": "Bearer …"}; файла нет — {}, и остаётся статический заголовок
# с токеном из настроек. Ни токена из настроек, ни CLAUDE_PLUGIN_DATA Claude Code помощнику
# не даёт (проверено вживую, 2.1.311), HOME — даёт. Поэтому файл появляется, только когда
# токена в настройках нет, а session_start.sh убирает его, когда токен в настройках задан.
# Claude Code зовёт помощник при подключении и по /mcp → Reconnect, но не сам после 401:
# токен, полученный посреди сессии, MCP возьмёт после Reconnect или в следующей сессии.
# POSIX sh; на Windows — Git Bash.

. "$(dirname -- "$0")/lib.sh"

if found=$(saved_token); then
	printf '{"Authorization": "Bearer %s"}\n' "$found"
else
	printf '{}\n'
fi
exit 0
