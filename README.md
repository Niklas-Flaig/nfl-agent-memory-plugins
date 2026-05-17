# agent-plugins

Private Claude Code plugin marketplace for plugins authored by Lord Niklas
Flaig. The marketplace manifest is at `.claude-plugin/marketplace.json` and
each plugin lives in its own top-level subdirectory.

## Plugins

| Plugin | Status | What it does |
|---|---|---|
| [`the-pensieve-plugin`](./the-pensieve-plugin) | Phase 1 | Routes Claude between repo-local docs and a cross-project Basic Memory vault. |

## Install the marketplace

From inside a Claude Code session:

```
/plugin marketplace add /Users/ephandor/emdash/repositories/agent-plugins
```

Then install any individual plugin:

```
/plugin install the-pensieve-plugin@niklas-agent-plugins
```

Per-plugin READMEs document their own prerequisites and configuration.
