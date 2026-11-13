# skills

Agent skills, in the open [Agent Skills](https://agentskills.io) layout (`skills/<name>/SKILL.md`), installable
with `npx skills` into Claude Code, Cursor, Codex, Gemini CLI and other compatible agents.

## Skills

| Skill | What it does |
|---|---|
| [`frontkar-sade`](skills/frontkar-sade/SKILL.md) | Interviews you about a project and every tech choice (each compared and with a recommendation), writes ADRs and a rendering/caching route map, scaffolds a Next.js 16 App Router project, and builds it in tested, reviewed vertical slices. Has Express and Full interview modes, and domain packs for fintech/exchange, e-commerce, dashboard/SaaS and content/media. |

## Install

```bash
# from GitHub (after pushing this repo)
npx skills add MoeeinAali/skills --skill frontkar-sade

# from this local checkout
npx skills add ./ --skill frontkar-sade

# Claude Code only, by hand
ln -s "$PWD/skills/frontkar-sade" ~/.claude/skills/frontkar-sade
```

Optional companion: the `paranoia` review skill. When it's installed, `frontkar-sade` runs it on the
architecture docs and on each slice. Without it, the bundled checklist (`references/quality-gates.md`) is used.

## Use

In your agent, start with the brief:

> Use frontkar-sade. Here's the project: <paste the definition>

It asks you to pick Express or Full mode, then walks through the decisions before writing any code.

A practice brief (Persian, business-only, no backend or tech details) is in
[`examples/brief-saraf.fa.md`](examples/brief-saraf.fa.md).
