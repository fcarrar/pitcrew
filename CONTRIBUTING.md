# Contributing to pitcrew

Thanks for taking a look! pitcrew is a small, self-contained set of Claude Code skills plus an
installer. Contributions that keep it **generic, config-driven, and safe-by-default** are very welcome.

## What's in the box

- `skills/<slug>/SKILL.md` — one crew member each. These are prompt files: the YAML frontmatter
  (`name`, `description`) is what Claude Code reads, and the body is the skill's instructions.
- `references/` — the shared contracts every skill leans on (config schema, topology, Linear-binding,
  directed-target). When you change how skills coordinate, update the reference doc **first**.
- `bin/install.sh` — symlinks skills into `~/.claude/commands/` and seeds runtime config.

There is no build step and no test suite to run — the "tests" are: does the installer wire things up,
and does each skill validate its config and behave on a real project.

## Ground rules

1. **Stay generic. No project-specific values, ever.** Skills must read everything project-specific
   from `config.json` (`repos[]`, `linear.*`, `github.*`, …). Don't hardcode a repo name, team ID,
   URL, ticket prefix, person, or label literal into a skill or reference doc. Use the example
   placeholders (`example-frontend`, `Example`/`EX-123`, `you@example.com`, `your-org`). A quick check
   before you push:

   ```bash
   grep -rinE 'TODO-your-real-org|your-real-team-uuid' skills references   # nothing real should leak
   ```

2. **Keep a lesson, drop the war story.** It's fine — encouraged — to encode hard-won rules ("use
   state IDs, not names, because name matching is fuzzy"). Just phrase them as the rule + the *why*,
   not as a dated incident tied to a private system.

3. **Safety gates are not optional.** If you touch the releaser, ops, or any skill that takes an
   outward action: preserve dev-before-prod, red-never-ships, per-repo arming, and agent-only scope.
   New autonomy is opt-in, per repo, and downgrades safely when its prerequisites aren't met.

4. **Config changes are a contract.** If a skill needs a new config field, add it to
   `references/config.example.json` (with a `_comment`) and document it in `references/SETUP.md`. Make
   it optional with a sane default where you can, so existing configs don't break.

5. **Update the topology when you change the shape.** Adding, removing, or rewiring a skill means
   updating `references/TOPOLOGY.md` (the "twelve skills" table + routing) and cross-referencing the
   skills that hand off to or from it.

## Adding or changing a skill

1. Read `references/TOPOLOGY.md` to see where the new role fits and what it hands off to.
2. Name it `/<verb>-run` for an autonomous loop, `/<verb>` for a human-in-the-loop skill. Pick a
   distinct verb (avoid noun collisions).
3. Write `skills/<slug>/SKILL.md` with frontmatter (`name`, `description`) and a **STEP −1: load
   config** block that validates required fields and exits cleanly with a pointer to `SETUP.md` if
   anything's missing — no half-runs against bad config.
4. Add the skill to the `SKILLS=(…)` list in `bin/install.sh`.
5. Test the install locally: `./bin/install.sh testproj`, then smoke the skill against a throwaway
   project config before opening a PR.

## Pull requests

- Keep PRs focused — one skill or one concern per PR where you can.
- Describe the behaviour change and how you smoke-tested it.
- If you changed coordination (states, labels, handoffs), call out which other skills you updated to match.

By contributing you agree your work is licensed under the repo's [MIT License](LICENSE).
