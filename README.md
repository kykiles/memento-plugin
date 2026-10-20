# Memento for Claude Code

This plugin connects Claude Code to Memento, a long-term memory server:

- the `memento` MCP server provides the memory tools (`memory_index`, `memory_recall`, `memory_remember`, `memory_episode` and others); the agent receives the rules for using memory from the server;
- a session start hook puts the memory index of the current project into context right away;
- a stop hook reminds the agent once per session to record an episode if there was work (a commit, a PR or file edits) and no episode was recorded.

## Installation

Run these two commands yourself in a terminal (PowerShell, bash or zsh), with your own token:

```
claude plugin marketplace add https://github.com/kykiles/memento-plugin.git
claude plugin install memento@memento-plugin --config url=https://memento.degulator.top --config token=<token>
```

Then restart Claude Code. Keep `--config url=…` even with the default server: Claude Code does not save the option's default value.

Do not paste the token into a Claude Code chat and do not ask the agent to install the plugin for you: whatever you paste stays in plain text in the session history, and auto mode blocks the install as a data leak. The token is kept in Claude Code's secure credential storage, not in the settings files. The command stays in your shell history; clear it if the machine is shared.

Alternatively, inside Claude Code:

```
/plugin marketplace add https://github.com/kykiles/memento-plugin.git
/plugin install memento@memento-plugin
```

Claude Code will ask for the server address (`https://memento.degulator.top`, without `/mcp`) and the token.

Do not add a separate `memento` MCP server with the same URL by hand: Claude Code then hides the plugin's server.

### Auto mode

Auto mode may block memory tools that send the project name to the server. Allow them in `~/.claude/settings.json` yourself (the agent cannot change its own permissions):

```json
{
  "permissions": {
    "allow": ["mcp__plugin_memento_memento"]
  }
}
```

## Projects

Memory is kept per project. The project is the `origin` remote of the git repository Claude Code was started in (`git@github.com:u/r.git` and `https://github.com/u/r` are the same project); without a remote, the folder name. A nested repository is a separate project, and a session started in the home folder gets a project named after it. Start Claude Code in the repository you work on; the project of a running session does not change.

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
