# Pipeline state templates

Project-local state templates for the `pipeline-*` skill family. These are
**committed** so the team shares one definition of the stages.

## Precedence

`pipeline-next` checks **project-local** templates here FIRST, then falls back to
the skill-default templates in the pipeline-skill's `templates/` directory
(resolved via `PIPELINE_SKILL_DIR` or the directory containing `pipeline.py`).
Files here therefore OVERRIDE the skill defaults.

## Files

- `feature-state.json` — 14 stages
- `bugfix-state.json` — 12 stages (Diagnosis / Fix / Regression Check)
- `refactor-state.json` — 12 stages (Analysis / Refactor Execution / Review)

Each was copied from the canonical template and parameterized for this repo:
`pr_target_branch = main`, test stage runs `terraform validate`, review stages
run `terraform fmt -check -recursive`.

## Committed vs ephemeral

- **Committed:** `.pipeline-templates/`, `ROADMAP.md`, `CHANGELOG.md`, `RETRO.md`,
  `docs/adr/`, `docs/strategy-sessions/`.
- **Ephemeral (gitignored):** `.pipeline-state/` contents and `.pipeline-log.md`
  — recreated per-checkout by `pipeline-next` / `pipeline-run`.
