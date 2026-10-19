#!/bin/sh
# Memento, SessionStart: оглавление памяти проекта — в контекст новой сессии.
# Проект — git remote папки проекта, без remote — имя папки. Адрес и токен — из настроек
# плагина (CLAUDE_PLUGIN_OPTION_URL, CLAUDE_PLUGIN_OPTION_TOKEN). Любой сбой — одна строка
# о недоступности и код 0: сессия стартует и без памяти. POSIX sh; на Windows — Git Bash.

down() {
	printf 'memento: недоступна (%s) — память не подгружена\n' "$1"
	exit 0
}

[ -n "$CLAUDE_PLUGIN_OPTION_TOKEN" ] || down "не задан токен"
[ -n "$CLAUDE_PLUGIN_OPTION_URL" ] || down "не задан адрес сервера"

dir=${CLAUDE_PROJECT_DIR:-$(pwd)}
name=$(git -C "$dir" remote get-url origin 2>/dev/null)
if [ -z "$name" ]; then
	# Путь Windows (C:\...) — с прямыми слэшами, чтобы basename взял имя папки.
	name=$(basename -- "$(printf '%s' "$dir" | tr '\134' /)")
fi

# Заголовок с токеном — через stdin (-H @-): аргументы процесса видны всем на машине.
out=$(printf 'Authorization: Bearer %s\n' "$CLAUDE_PLUGIN_OPTION_TOKEN" |
	curl -fsS --max-time 2 --get --data-urlencode "project=$name" -H @- \
		"${CLAUDE_PLUGIN_OPTION_URL%/}/v1/index" 2>&1)
code=$?
if [ "$code" -ne 0 ]; then
	last=$(printf '%s\n' "$out" | tail -n 1)
	case $code in
	22) down "HTTP $(printf '%s' "$last" | sed -n 's/.*error: *\([0-9][0-9]*\).*/\1/p')" ;;
	28) down "нет ответа за 2 с" ;;
	*) down "нет связи: $(printf '%s' "$last" | sed 's/^curl: ([0-9]*) //')" ;;
	esac
fi

case $out in
*[![:space:]]*)
	printf 'memento: оглавление памяти проекта %s (значения — memory_recall)\n%s\n' \
		"$name" "$out"
	;;
*) printf 'memento: в памяти проекта %s пока пусто\n' "$name" ;;
esac
exit 0
