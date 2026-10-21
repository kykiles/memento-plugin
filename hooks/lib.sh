#!/bin/sh
# Memento: общее для хуков реплики и хода (user_prompt.sh, stop.sh); подключается через `.`.
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

# post ПУТЬ ТЕЛО СЕКУНДЫ — POST JSON на сервер, ответ (текст) — в stdout; сбой — код ≠ 0 и
# пустой вывод. Токен и тело — конфигом curl через stdin (-K -): аргументы процесса видны
# всем на машине, а stdin один. Конфиг построчный: переводы строк в теле — только пробелы
# между токенами JSON (внутри строк JSON их нет), их заменяет пробел.
post() {
	{
		printf 'header = "Authorization: Bearer %s"\n' \
			"$(printf '%s' "$CLAUDE_PLUGIN_OPTION_TOKEN" | conf)"
		printf 'header = "Content-Type: application/json"\ndata-binary = "'
		printf '%s\n' "$2" | conf | tr '\n\r' '  '
		printf '"\n'
	} | curl -fsS --max-time "$3" -K - "${url%/}$1" 2>/dev/null
}
