# Memento для Claude Code

Плагин подключает к Claude Code долговременную память Memento:

- MCP-сервер `memento` — инструменты памяти (`memory_index`, `memory_recall`, `memory_remember`, `memory_episode` и другие); правила работы с памятью агент получает от сервера;
- хук начала сессии — оглавление памяти текущего проекта сразу в контексте;
- хук конца ответа — один раз за сессию напоминает записать эпизод, если была работа (коммит, PR или правки файлов), а эпизод не записан.

## Установка

В Claude Code:

```
/plugin marketplace add kykiles/memento-plugin
/plugin install memento@memento-plugin
```

Claude Code спросит адрес сервера (по умолчанию `https://memento.degulator.top`, без `/mcp`) и токен. Токен хранится в защищённом хранилище Claude Code, а не в файлах настроек.

## Токен

Токен выдаёт владелец сервера Memento — свой для каждого пользователя:

```
python -m memento token add claude-code --rights write --user <логин>
```

## Что нужно

- Git. На Windows — [Git for Windows](https://gitforwindows.org/): его `bash` запускает хуки плагина. Без него хуки не сработают, но MCP-сервер работает: оглавление агент возьмёт сам вызовом `memory_index`.
- `curl` — есть в Git for Windows, macOS и большинстве Linux.

## Лицензия

MIT — см. [LICENSE](LICENSE).
