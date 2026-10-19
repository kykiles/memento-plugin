# Memento for Claude Code

This plugin connects Claude Code to Memento, a long-term memory server:

- the `memento` MCP server provides the memory tools (`memory_index`, `memory_recall`, `memory_remember`, `memory_episode` and others); the agent receives the rules for using memory from the server;
- a session start hook puts the memory index of the current project into context right away;
- a stop hook reminds the agent once per session to record an episode if there was work (a commit, a PR or file edits) and no episode was recorded.

## Installation

Run one command in a terminal (PowerShell, bash or zsh), on one line, with your own token:

```
claude plugin install memento --marketplace kykiles/memento-plugin --config url=https://memento.degulator.top --config token=<token>
```

Then restart Claude Code. Keep `--config url=…` even with the default server: Claude Code does not save the option's default value, and the hooks need it.

The token is kept in Claude Code's secure credential storage, not in the settings files. The command stays in your shell history; clear it if the machine is shared.

Alternatively, inside Claude Code:

```
/plugin marketplace add kykiles/memento-plugin
/plugin install memento@memento-plugin
```

Claude Code will ask for the server address (`https://memento.degulator.top`, without `/mcp`) and the token.

Do not add a separate `memento` MCP server with the same URL by hand: Claude Code then hides the plugin's server.

## Check

- `/mcp` in Claude Code lists `plugin:memento:memento` as connected;
- a new session in a project starts with the line `memento: оглавление памяти проекта …` (the memory index; empty in a new project).

## Token

The owner of the Memento server issues each user their own token:

```
python -m memento token add claude-code --rights write --user <login>
```

## Requirements

- Git. On Windows, [Git for Windows](https://gitforwindows.org/): its `bash` runs the plugin's hooks. Without it the hooks do not run, but the MCP server works: the agent gets the memory index itself by calling `memory_index`.
- `curl`: included in Git for Windows, macOS and most Linux distributions.

## Removal

```
claude plugin uninstall memento@memento-plugin
```

## License

MIT, see [LICENSE](LICENSE).
