# Memento for Claude Code

This plugin connects Claude Code to Memento, a long-term memory server:

- the `memento` MCP server provides the memory tools (`memory_index`, `memory_recall`, `memory_remember`, `memory_episode` and others); the agent receives the rules for using memory from the server;
- a session start hook puts the memory index of the current project into context right away;
- a prompt hook and a turn-end hook keep a trimmed episode of every session on the server (the auto-episode) and, at a moment worth remembering, give the agent one line asking it to record a fact: a correction, "remember this", an agreed decision, "important", or a problem solved after several failed commands. No such moment, no line.

## What is sent to the server

On every prompt (`UserPromptSubmit`): the project name, your prompt text and the hook event as Claude Code passes it (session id, transcript path, working folder, permission mode).

At the end of every agent turn (`Stop`): the project name, the hook event (session id, transcript path, working folder, permission mode, the agent's final message of the turn, and the list of running background tasks with their commands), and from the session transcript:

- file paths the agent edited in this session (`Edit`, `Write`, `NotebookEdit`);
- commit hashes and commit subjects made in the project since the session started;
- how many commands failed in this turn, whether the last one succeeded, whether the agent called `memory_remember`, and whether the session used `WebFetch`, `WebSearch` or a non-Memento MCP tool (such sessions are marked untrusted).

Command output (tool results, stdout and stderr) and file contents are never sent. The server keeps only the session id, the prompts, the final message, file paths and commit subjects; it cuts known secret patterns (tokens, passwords) before storing, and drops everything else from the event.

### Turning the auto-episode off

In Claude Code, open `/config` and switch off the plugin's «Автоэпизод» option (`auto_episode`, on by default). Restart Claude Code to be sure the hooks pick up the change. With the auto-episode off, the hooks still send prompts and turn signals to get the one-line hints, but the server stores nothing. To send nothing at all, uninstall the plugin or disable it in `/plugin`.

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

## Updates

Claude Code does not update plugins from third-party marketplaces unless you turn it on. Turn it on once: in Claude Code, `/plugin` → Marketplaces → `memento-plugin` → Enable auto-update. Claude Code then fetches new versions at startup; a new version takes effect after a restart.

To update by hand:

```
claude plugin marketplace update memento-plugin
claude plugin update memento@memento-plugin
```

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
