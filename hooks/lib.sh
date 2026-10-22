#!/bin/sh
# Memento: общее для хуков реплики, хода и досылки (user_prompt.sh, stop.sh, flush.sh);
# подключается через `.`.
# Проект — git remote папки проекта, без remote — имя папки (как в session_start.sh). Адрес
# и токен — из настроек плагина; адрес по умолчанию Claude Code в настройки не сохраняет —
# он и здесь по умолчанию. POSIX sh; на Windows — Git Bash.

url=${CLAUDE_PLUGIN_OPTION_URL:-https://memento.degulator.top}
dir=${CLAUDE_PROJECT_DIR:-$(pwd)}
project=$(git -C "$dir" remote get-url origin 2>/dev/null)
if [ -z "$project" ]; then
	# Путь Windows (C:\...) — с прямыми слэшами, чтобы basename взял имя папки.
	project=$(basename -- "$(printf '%s' "$dir" | tr '\134' /)")
fi

# Выключатель автоэпизода (userConfig auto_episode, boolean): Claude Code отдаёт его строкой
# true/false, а значение по умолчанию не сохраняет — пусто значит включён. Сервер без
# `store: true` автоэпизод не пишет, строку момента отдаёт.
case $CLAUDE_PLUGIN_OPTION_AUTO_EPISODE in
false | False | FALSE | 0 | no | off) store=false ;;
*) store=true ;;
esac

# Строка JSON из текста: \ и " экранируются, перевод строки и прочие управляющие символы —
# пробел (в строке JSON их быть не может).
quote() {
	printf '"%s"' "$(printf '%s' "$1" | tr '\n' ' ' | sed 's/[\\"]/\\&/g; s/[[:cntrl:]]/ /g')"
}

# Экранирование для строки в кавычках конфига curl: \ и ".
conf() {
	sed 's/[\\"]/\\&/g'
}

# request ПУТЬ ТЕЛО СЕКУНДЫ ФЛАГИ… — POST JSON на сервер, флаги — дополнительные для curl,
# вывод curl — в stdout. Токен и тело — конфигом curl через stdin (-K -): аргументы процесса
# видны всем на машине, а stdin один. Конфиг построчный: переводы строк в теле — только
# пробелы между токенами JSON (внутри строк JSON их нет), их заменяет пробел.
request() {
	r_path=$1 r_body=$2 r_secs=$3
	shift 3
	{
		printf 'header = "Authorization: Bearer %s"\n' \
			"$(printf '%s' "$CLAUDE_PLUGIN_OPTION_TOKEN" | conf)"
		printf 'header = "Content-Type: application/json"\ndata-binary = "'
		printf '%s\n' "$r_body" | conf | tr '\n\r' '  '
		printf '"\n'
	} | curl -sS "$@" --max-time "$r_secs" -K - "${url%/}$r_path" 2>/dev/null
}

# post ПУТЬ ТЕЛО СЕКУНДЫ — ответ сервера (текст) — в stdout; сбой — код ≠ 0 и пустой вывод.
post() {
	request "$1" "$2" "$3" -f
}

# Очередь досылки (плагин 0.3.1): реплика и итог хода, которые не дошли до сервера, ждут в
# каталоге данных плагина, пока их не дошлёт flush.sh. Без каталога данных очереди нет.
q=
[ -z "$CLAUDE_PLUGIN_DATA" ] || q=$CLAUDE_PLUGIN_DATA/queue

# enqueue ИМЯ ПУТЬ ТЕЛО — файл очереди ИМЯ: первая строка — путь маршрута, вторая — тело
# одной строкой (переводы строк — пробелы, как в post). Токена в файле нет. Пишется во
# временный файл и переносится mv — flush.sh не увидит половины; файл с тем же именем
# заменяется. В очереди уже 500 файлов — не пишется. Реплики — только владельцу, как
# транскрипты Claude Code: umask 077 (каталог 700, файлы 600). Любой сбой — молча.
enqueue() {
	[ -n "$q" ] || return 0
	(
		umask 077
		mkdir -p "$q" 2>/dev/null || exit 0
		[ "$(ls "$q" 2>/dev/null | wc -l)" -lt 500 ] || exit 0
		{
			printf '%s\n' "$2"
			printf '%s\n' "$3" | tr '\n\r' '  '
			printf '\n'
		} >"$q/.new-$$" 2>/dev/null && mv -f "$q/.new-$$" "$q/$1" 2>/dev/null
		rm -f "$q/.new-$$" 2>/dev/null
	)
	return 0
}

# session — session_id события ($event) только из [A-Za-z0-9-]: имя файла очереди.
session() {
	printf '%s\n' "$event" | LC_ALL=C grep -a -o -E '"session_id": *"(\\.|[^"\\])*"' | head -n 1 |
		sed 's/^"session_id": *"//; s/"$//' | LC_ALL=C tr -cd 'A-Za-z0-9-'
}
