# nfl-agent-memory-plugins

Niklas Flaig's private Claude Code plugin marketplace, dedicated to
**agentic memory** — knowledge architecture, vault routing, drift
detection, cross-project context, and the surrounding tooling.

The marketplace manifest lives at `.claude-plugin/marketplace.json`. Each
plugin is a top-level subdirectory with its own `.claude-plugin/plugin.json`,
README, and component folders (`hooks/`, `rules/`, `skills/`, `commands/`,
`agents/`, `scripts/`).

## Plugins

| Plugin | Status | What it does |
|---|---|---|
| [`the-pensieve-plugin`](./the-pensieve-plugin) | Phases 1–3 shipped | Routes Claude between repo-local docs and a cross-project Basic Memory vault. Session-start drift detection, 4 skills, 4 slash commands. |

More to come — anything that helps an agent remember, recall, retrieve,
or reconcile knowledge will live here.

## Install the marketplace

From inside a Claude Code session:

```
/plugin marketplace add Niklas-Flaig/nfl-agent-memory-plugins
```

Then install any individual plugin:

```
/plugin install the-pensieve-plugin@nfl-agent-memory-plugins
```

Per-plugin READMEs document their own prerequisites and configuration.
