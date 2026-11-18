# vale-voices-hook

A hook for Claude Code and Codex that lints Markdown and AsciiDoc with [Vale](https://vale.sh) and the [Voices](https://github.com/jdkato/voices) styles after every edit.

Error-level alerts go straight back to the agent, so it fixes the prose before moving on.
Setup problems (no `vale`, no `jq`) go to *you* as a one-line warning, never to the agent.

Example of what the agent sees after a bad edit:

```text
Vale reports 3 error-level alert(s):
  docs/install.md:3: Voices.InflatedWords [error] — Inflated word: use 'using' instead of 'leveraging'.
  docs/install.md:3: Voices.WeakVerbs [error] — Weak verb phrase: use 'to' instead of 'in order to'.
  docs/install.md:3: Direct.Ease [error] — This paragraph scores -2.00 on reading ease. Keep it above 50: short words, short sentences.

Fix these before moving on, preserving the markup exactly. Do not disable a rule to clear one.
```

## Prerequisites

- [Vale](https://vale.sh/docs/install) 3.x on your `PATH`.
- `jq` on your `PATH`.

## Installing in Claude Code

Add the marketplace and install the plugin:

```text
/plugin marketplace add aireilly/vale-voices-hook
/plugin install vale-voices@vale-voices
```

Restart Claude Code.
On the first session start, the plugin runs `vale sync` to download the Voices styles (about 60 seconds at most).
After that, every `Edit`, `Write`, or `MultiEdit` on a `.md` or `.adoc` file gets checked.

## Installing in Codex

Codex has no plugin hooks here, so you wire it up by hand.

1. Clone the repo and download the styles:

   ```console
   $ git clone https://github.com/aireilly/vale-voices-hook.git
   $ cd vale-voices-hook
   $ vale --config=vale/.vale.ini sync
   ```

2. Copy `codex/hooks.json` to `~/.codex/hooks.json`, replacing `<repo_path>` with the clone's absolute path.

Done!

## Configuring

The bundled `vale/.vale.ini` turns on `Voices` and `Direct` at error level, with sentences capped at 35 words.
The Voices package also ships `Claude`, `Coach`, `GenZ`, `Human`, `Simple`, and `Std`, so add any of them to `BasedOnStyles` if you want them.

To use your own config, set these environment variables:

- `VALE_CONFIG` is the path to your `.vale.ini`. Vale resolves `StylesPath` relative to it.
- `VALE_BIN` is the Vale binary to run, if it isn't `vale` on your `PATH`.

## Testing

```console
$ sh tests/run.sh
```

The tests feed Claude (`Write`, `Edit`, `MultiEdit`) and Codex (`apply_patch`) payloads to the hook and check the output.

## Credits

Adapted from `vale-cli/agent-tools/hooks/vale-edit.sh`.
The styles come from [jdkato/voices](https://github.com/jdkato/voices).
