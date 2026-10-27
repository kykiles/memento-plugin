#!/bin/sh
# Memento, вход по ссылке с кодом (SessionStart, фоном — "async": true; плагин 0.4.0): ждёт,
# пока пользователь подтвердит код из ссылки session_start.sh, и кладёт токен в файл
# ~/.config/memento/token (600, каталог 700; путь — saved в lib.sh). Токен в настройках или
# уже в файле — сразу выход. Код — из файла ожидания login (его пишет session_start.sh, запущенный вместе с этим
# хуком: ждать его до 15 с). Опрос POST /v1/device/token — раз в interval секунд (RFC 8628:
# slow_down — интервал +5 с), до срока кода; ответы: токен — в файл; authorization_pending и
# сбой сети или сервера — ждать дальше; access_denied, expired_token, invalid_grant — выход,
# следующая сессия начнёт заново. Файл ожидания тогда убирается, если в нём всё ещё этот код;
# появился новый код — опрос переходит на него. Один опрос за раз — замок mkdir; замок старше
# 10 минут — от убитого запуска: снять. device_code и токен — только в теле запроса через
# stdin curl (request в lib.sh), не в аргументах процесса; stdout пуст. Любой сбой — молча и
# код 0. POSIX sh; на Windows — Git Bash.

cat >/dev/null
. "$(dirname -- "$0")/lib.sh"
token && exit 0
[ -n "$CLAUDE_PLUGIN_DATA" ] && [ -n "$saved" ] || exit 0
wait=$CLAUDE_PLUGIN_DATA/login

# fresh — файл ожидания есть и моложе 10 минут (старый — от прежней сессии, его заменит
# session_start.sh).
fresh() {
	[ -f "$wait" ] && [ -z "$(find "$wait" -mmin +10 2>/dev/null)" ]
}
n=0
until fresh; do
	[ "$n" -lt 15 ] || exit 0
	sleep 1
	n=$((n + 1))
done

lock=$CLAUDE_PLUGIN_DATA/login.lock
if ! mkdir "$lock" 2>/dev/null; then
	[ -n "$(find "$lock" -prune -mmin +10 2>/dev/null)" ] || exit 0
	rmdir "$lock" 2>/dev/null
	mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT
trap 'exit 0' HUP INT TERM

# drop КОД — код погашен, отвергнут или истёк: файл ожидания — прочь, если в нём всё ещё он.
drop() {
	[ "$(sed -n 1p "$wait" 2>/dev/null)" != "$1" ] || rm -f "$wait"
	exit 0
}

# keep ТОКЕН — в файл токена: временный файл и mv, umask 077 — файл 600, каталог 700.
keep() {
	(
		umask 077
		mkdir -p "${saved%/*}" && chmod 700 "${saved%/*}" &&
			printf '%s\n' "$1" >"$saved.new-$$" && mv -f "$saved.new-$$" "$saved"
		rm -f "$saved.new-$$"
	) 2>/dev/null
}

current=
while :; do
	device_code=$(sed -n 1p "$wait" 2>/dev/null)
	case $device_code in '' | *[!A-Za-z0-9_]*) exit 0 ;; esac
	if [ "$device_code" != "$current" ]; then
		current=$device_code
		interval=$(sed -n 4p "$wait" 2>/dev/null)
		expires=$(sed -n 5p "$wait" 2>/dev/null)
		case $interval in '' | *[!0-9]* | 0) interval=5 ;; esac
		case $expires in '' | *[!0-9]*) drop "$device_code" ;; esac
	fi
	[ "$(date +%s)" -lt "$expires" ] || drop "$device_code"
	touch "$lock" 2>/dev/null
	sleep "$interval"
	answer=$(request /v1/device/token "{\"device_code\": \"$device_code\"}" 5)
	got=$(field token)
	case $got in
	'' | *[!A-Za-z0-9_]*) ;;
	*)
		keep "$got"
		drop "$device_code"
		;;
	esac
	case $(field error) in
	slow_down) interval=$((interval + 5)) ;;
	access_denied | expired_token | invalid_grant) drop "$device_code" ;;
	esac
done
