#!/bin/sh
# Memento: общее для хуков плагина (session_start.sh, user_prompt.sh, stop.sh, flush.sh,
# login.sh) и помощника заголовков MCP (headers.sh); подключается через `.`.
# Проект — git remote папки проекта, без remote — имя папки. Адрес — из настроек плагина;
# адрес по умолчанию Claude Code в настройки не сохраняет — он и здесь по умолчанию. Токен —
# только через token (ниже). POSIX sh; на Windows — Git Bash.

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

# Токен плагина (0.4.0): из настроек (CLAUDE_PLUGIN_OPTION_TOKEN), если задан, иначе — файл
# ~/.config/memento/token (XDG_CONFIG_HOME, как у gh): его кладёт login.sh после входа по
# ссылке с кодом (права 600, каталог 700). Файл читает и помощник заголовков MCP (headers.sh):
# ему Claude Code не даёт ни токен из настроек, ни CLAUDE_PLUGIN_DATA, а HOME даёт. Токен —
# только в переменных и в stdin curl, не в аргументах процесса.
secret= from=
saved=
config=${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}
[ -z "$config" ] || saved=$config/memento/token

# saved_token — токен из файла входа — в stdout; файла нет или в нём не токен — код 1.
saved_token() {
	[ -n "$saved" ] && [ -f "$saved" ] || return 1
	s_line=
	IFS= read -r s_line 2>/dev/null <"$saved"
	case $s_line in
	'' | *[!A-Za-z0-9_]*) return 1 ;;
	esac
	printf '%s' "$s_line"
}

# token — токен плагина в $secret, откуда он — в $from (settings или file): настройки важнее
# файла. Нет ни того, ни другого — код 1.
token() {
	if [ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ]; then
		secret=$CLAUDE_PLUGIN_OPTION_TOKEN from=settings
		return 0
	fi
	secret=$(saved_token) || {
		secret=
		return 1
	}
	from=file
}

# forget — сервер ответил 401 на токен из файла: вход отозван, файл удаляется (если в нём всё
# ещё этот токен), следующая сессия даст ссылку заново. Токен из настроек не трогается.
forget() {
	[ "$from" = file ] && [ "$(saved_token)" = "$secret" ] && rm -f "$saved" 2>/dev/null
	return 0
}

# field ИМЯ — значение поля ИМЯ ответа сервера ($answer, JSON): строка без кавычек или число.
# Только простые строки — без \ и ", иначе пусто.
field() {
	printf '%s\n' "$answer" | LC_ALL=C grep -a -o -E "\"$1\" *: *(\"[^\"\\\\]*\"|[0-9]+)" |
		head -n 1 | sed 's/^"[^"]*" *: *//; s/^"//; s/"$//'
}

# request ПУТЬ ТЕЛО СЕКУНДЫ ФЛАГИ… — POST JSON на сервер, флаги — дополнительные для curl,
# вывод curl — в stdout. Токен ($secret; пуст — запрос без него) и тело — конфигом curl через
# stdin (-K -): аргументы процесса видны всем на машине, а stdin один. Конфиг построчный:
# переводы строк в теле — только пробелы между токенами JSON (внутри строк JSON их нет), их
# заменяет пробел.
request() {
	r_path=$1 r_body=$2 r_secs=$3
	shift 3
	{
		[ -z "$secret" ] || printf 'header = "Authorization: Bearer %s"\n' \
			"$(printf '%s' "$secret" | conf)"
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
