#!/bin/sh
# Memento, досылка (SessionStart и Stop, фоном — "async": true): реплики и итоги хода, которые
# user_prompt.sh и stop.sh не смогли отправить (сервер был недоступен), — на сервер. Очередь —
# каталог данных плагина: файл — путь маршрута и тело одной строкой, токена в нём нет. Сначала
# реплики по времени, затем итоги хода; не больше 20 файлов за запуск (частота сервера — 60 в
# минуту). Ответ 2xx — файл удаляется; ответ, который сервер не примет и при повторе (400, 401,
# 403, 404, 413, 422), — тоже; всё остальное (нет сети — 000, 429, 5xx) — запуск
# останавливается, файлы ждут следующего. Ответ сервера (строка момента) не нужен: stdout пуст.
# Файлы старше 14 дней удаляются без отправки. Один запуск за раз — замок mkdir. Любой сбой —
# молча и код 0. POSIX sh; на Windows — Git Bash.

[ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || exit 0
event=$(cat)
. "$(dirname -- "$0")/lib.sh"
[ -n "$q" ] && [ -d "$q" ] || exit 0

# Замок: каталог создаётся атомарно. Замок старше 10 минут — от убитого запуска: снять.
lock=$q/.lock
if ! mkdir "$lock" 2>/dev/null; then
	[ -n "$(find "$lock" -prune -mmin +10 2>/dev/null)" ] || exit 0
	rmdir "$lock" 2>/dev/null
	mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT
trap 'exit 0' HUP INT TERM

find "$q" -type f -mtime +14 -exec rm -f {} + 2>/dev/null

# Итог хода своей сессии шлёт stop.sh: в Stop они идут одновременно, и досланный здесь
# прежний итог мог бы прийти позже нового.
sid=$(session)
sent=0
for name in $(ls "$q" | LC_ALL=C grep -E '^p-[0-9]+-[0-9]+$' | sort -t- -k2,2n -k3,3n) \
	$(ls "$q" | LC_ALL=C grep -E '^s-[A-Za-z0-9-]+$'); do
	[ "$name" != "s-$sid" ] || continue
	[ "$sent" -lt 20 ] || break
	sent=$((sent + 1))
	file=$q/$name
	code=$(request "$(sed -n 1p "$file")" "$(sed -n 2p "$file")" 5 -o /dev/null -w '%{http_code}')
	case $code in
	2?? | 400 | 401 | 403 | 404 | 413 | 422) rm -f "$file" ;;
	*) break ;;
	esac
done
exit 0
