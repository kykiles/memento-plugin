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

### When the server is unreachable

If a prompt or a turn end cannot reach the server (no network, server down, too many requests), the hooks keep it in a queue in the plugin's data folder (`queue` in `${CLAUDE_PLUGIN_DATA}`): one file per prompt and one per session for the turn end (a newer turn end replaces the older one). Each file holds only the server route and the same request body as above; the token is never written there. A background hook sends the queue at the next session start or turn end, up to 20 files at a time, and deletes each file once the server has taken it or refused it for good. Files wait up to 14 days, then are deleted unsent; the queue holds at most 500 files. While the server is reachable, nothing is kept locally. With the auto-episode off, nothing is queued.

### Turning the auto-episode off

In Claude Code, open `/config` and switch off the plugin's «Автоэпизод» option (`auto_episode`, on by default). Restart Claude Code to be sure the hooks pick up the change. With the auto-episode off, the hooks still send prompts and turn signals to get the one-line hints, but the server stores nothing. To send nothing at all, uninstall the plugin or disable it in `/plugin`.

## Installation

Run these two commands in a terminal (PowerShell, bash or zsh). No token is needed:

```
claude plugin marketplace add https://github.com/kykiles/memento-plugin.git
claude plugin install memento@memento-plugin --config url=https://memento.degulator.top
```

Then restart Claude Code and sign in (see below). Keep `--config url=…` even with the default server: Claude Code does not save the option's default value.

Alternatively, inside Claude Code:

```
/plugin marketplace add https://github.com/kykiles/memento-plugin.git
/plugin install memento@memento-plugin
```

Claude Code will ask for the server address (`https://memento.degulator.top`, without `/mcp`) and a token; leave the token empty.

## Sign in

The first session after installing shows one line: `Memento: войдите — https://memento.degulator.top/device?code=XXXX-XXXX (код XXXX-XXXX)`. Open the link, sign in with GitHub, check that the code on the page matches and press «Разрешить». The line is shown to you only; the agent does not see it. A background hook waits for your answer for up to 10 minutes and then keeps the plugin's token in `~/.config/memento/token` (`$XDG_CONFIG_HOME/memento/token` if set; readable only by you). The hooks use it at once; the memory tools pick it up after `/mcp` → `plugin:memento:memento` → Reconnect, or in the next session, which also starts with the memory index.

The server issues a new code at most once every 10 minutes: sessions started meanwhile show the same link. If you deny access or the code expires, the next session shows a new link.

If the token is revoked on the server, the plugin deletes the file and the next session asks you to sign in again.

### Token instead of sign-in

The owner of a Memento server can also issue a token by hand (see [Token](#token)). Pass it at install time:

```
claude plugin install memento@memento-plugin --config url=https://memento.degulator.top --config token=<token>
```

A token in the settings takes precedence over the sign-in: the plugin then works as 0.3.1 and deletes the sign-in file. Do not paste the token into a Claude Code chat and do not ask the agent to install the plugin for you: whatever you paste stays in plain text in the session history, and auto mode blocks the install as a data leak. The token is kept in Claude Code's secure credential storage, not in the settings files. The command stays in your shell history; clear it if the machine is shared.

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

Not needed with sign-in. To use a token instead, the owner of the Memento server issues it:

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

Uninstalling keeps the sign-in token; delete `~/.config/memento/token` yourself.

## License

MIT, see [LICENSE](LICENSE).
