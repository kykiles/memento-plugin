#!/bin/sh
# Memento, SessionStart: оглавление памяти проекта — в контекст новой сессии.
# Проект — git remote папки проекта, без remote — имя папки. Адрес — из настроек плагина
# (CLAUDE_PLUGIN_OPTION_URL); адрес по умолчанию Claude Code в настройки не сохраняет — он и
# здесь по умолчанию. Токен — из настроек (CLAUDE_PLUGIN_OPTION_TOKEN), иначе — из файла входа
# по ссылке с кодом (token в lib.sh). Любой сбой — одна строка о недоступности и код 0:
# сессия стартует и без памяти. POSIX sh; на Windows — Git Bash.
#
# Вход по ссылке с кодом (плагин 0.4.0): токена нет ни в настройках, ни в файле — код
# устройства с сервера (POST /v1/device/code) и одна строка пользователю через JSON
# systemMessage: ссылка и код; в контекст модели не уходит ничего. Ждёт подтверждения и
# кладёт токен в файл login.sh (фоном). Новый код — не чаще раза в 10 минут: до тех пор
# сессии показывают прежнюю ссылку (метка — возраст файла ожидания login в каталоге данных
# плагина). Сервер ответил 401 на токен из файла — вход отозван: файл удаляется, следующая
# сессия даёт ссылку заново.

. "$(dirname -- "$0")/lib.sh"

down() {
	printf 'memento: недоступна (%s) — память не подгружена\n' "$1"
	exit 0
}

# tell ТЕКСТ — строка пользователю (systemMessage), модели — ничего.
tell() {
	printf '{"systemMessage": %s}\n' "$(quote "Memento: $1")"
	exit 0
}

# why КОД ВЫВОД — причина сбоя curl (-fsS, --max-time 4) одной фразой.
why() {
	w_last=$(printf '%s\n' "$2" | tail -n 1)
	case $1 in
	22) printf 'HTTP %s' "$(printf '%s' "$w_last" | sed -n 's/.*error: *\([0-9][0-9]*\).*/\1/p')" ;;
	28) printf 'нет ответа за 4 с' ;;
	*) printf 'нет связи: %s' "$(printf '%s' "$w_last" | sed 's/^curl: ([0-9]*) //')" ;;
	esac
}

# login — ссылка и код входа пользователю. Файл ожидания (600, каталог 700): device_code,
# user_code, ссылка, интервал опроса, срок кода (секунды эпохи) — по строке; его читает
# login.sh. device_code не показывается: по нему выдаётся токен.
login() {
	wait=$CLAUDE_PLUGIN_DATA/login
	user_code= uri=
	if [ -f "$wait" ] && [ -z "$(find "$wait" -mmin +10 2>/dev/null)" ]; then
		user_code=$(sed -n 2p "$wait" 2>/dev/null)
		uri=$(sed -n 3p "$wait" 2>/dev/null)
	fi
	if [ -z "$user_code" ] || [ -z "$uri" ]; then
		answer=$(curl -fsS --max-time 4 -H 'Content-Type: application/json' \
			-d '{"client": "claude-code"}' "${url%/}/v1/device/code" 2>&1)
		code=$?
		[ "$code" -eq 0 ] || tell "недоступна ($(why "$code" "$answer")) — вход не начат"
		device_code=$(field device_code)
		user_code=$(field user_code)
		uri=$(field verification_uri_complete)
		interval=$(field interval)
		ttl=$(field expires_in)
		case $device_code in '' | *[!A-Za-z0-9_]*) device_code= ;; esac
		case $user_code in '' | *[!A-Za-z0-9-]*) user_code= ;; esac
		case $uri in http://* | https://*) ;; *) uri= ;; esac
		[ -n "$device_code" ] && [ -n "$user_code" ] && [ -n "$uri" ] ||
			tell "недоступна (непонятный ответ сервера) — вход не начат"
		case $interval in '' | *[!0-9]*) interval=5 ;; esac
		case $ttl in '' | *[!0-9]*) ttl=600 ;; esac
		(
			umask 077
			mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null && chmod 700 "$CLAUDE_PLUGIN_DATA" &&
				printf '%s\n' "$device_code" "$user_code" "$uri" "$interval" \
					"$(($(date +%s) + ttl))" >"$wait.new-$$" &&
				mv -f "$wait.new-$$" "$wait"
			rm -f "$wait.new-$$"
		) 2>/dev/null
	fi
	tell "войдите — $uri (код $user_code)"
}

# Токен в настройках — как в 0.3.1. Файл прежнего входа по ссылке тогда убирается: помощник
# заголовков MCP (headers.sh) настроек не видит и отдал бы токен из файла.
[ -z "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || [ -z "$saved" ] || rm -f "$saved" 2>/dev/null
if ! token; then
	[ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$saved" ] || down "не задан токен"
	login
fi

# Заголовок с токеном — через stdin (-H @-): аргументы процесса видны всем на машине.
out=$(printf 'Authorization: Bearer %s\n' "$secret" |
	curl -fsS --max-time 4 --get --data-urlencode "project=$project" -H @- \
		"${url%/}/v1/index" 2>&1)
code=$?
if [ "$code" -ne 0 ]; then
	reason=$(why "$code" "$out")
	[ "$reason" != "HTTP 401" ] || forget
	down "$reason"
fi

case $out in
*[![:space:]]*)
	printf 'memento: оглавление памяти проекта %s (значения — memory_recall)\n%s\n' \
		"$project" "$out"
	;;
*) printf 'memento: в памяти проекта %s пока пусто\n' "$project" ;;
esac
exit 0
