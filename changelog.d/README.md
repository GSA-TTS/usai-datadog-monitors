# changelog.d — CHANGELOG fragment files

Every monitor/dashboard PR used to append to the **same `### Added` list head**
in `CHANGELOG.md`, so each PR conflicted with its siblings the instant one
merged. Four consecutive PRs (#29/#30/#31/#32) paid that three-way-merge tax
(GitHub #35). The collision is *section-local*: two PRs editing `### Added`
collide; a PR editing `### Changed` does not.

**The fix**: each PR drops a small standalone fragment file in this directory
instead of editing `CHANGELOG.md`. Two PRs never touch the same file, so they
never conflict. At release time the fragments are concatenated into
`CHANGELOG.md` under `[Unreleased]` and deleted.

This is the [towncrier](https://towncrier.readthedocs.io/) / scriv pattern,
kept deliberately toolchain-free — a POSIX shell assembler
(`scripts/assemble-changelog.sh`), no Python dependency dragged into a
Terraform repo.

## Add a fragment (per PR)

Create one file per change: `changelog.d/<pr-or-issue>-<slug>.<type>.md`

- `<pr-or-issue>` — the PR number (or issue number if the PR isn't cut yet),
  purely to keep filenames unique and greppable.
- `<slug>` — a couple of kebab-case words.
- `<type>` — one of the Keep a Changelog section names, lower-cased:
  `added` · `changed` · `deprecated` · `removed` · `fixed` · `security`.

The file body is the changelog bullet(s) — Markdown, no leading `- ` (the
assembler adds it), one logical change per file. Example:

```
changelog.d/36-threshold-locals.changed.md
```
```markdown
Bound the drift-prone monitor thresholds to shared `locals` (#33) …
```

## Assemble at release

```bash
scripts/assemble-changelog.sh          # fold fragments into CHANGELOG.md [Unreleased], then rm them
scripts/assemble-changelog.sh --check  # CI/dry-run: list pending fragments, touch nothing
```

Fragments are grouped by Keep a Changelog type. Bullets for a type that already
has a `### <Type>` subsection under `[Unreleased]` are merged into it (inserted
at the top). Types with **no** existing subsection are appended *after* the
section's existing content, ordered canonically (Added, Changed, Deprecated,
Removed, Fixed, Security) **among themselves** — the assembler never moves a
subsection that's already there, so a pre-existing `### Fixed` can end up before
a newly-created `### Added`. Re-sort by hand at release if strict Keep a
Changelog ordering matters. The assembler only *adds* fragment content — it
never rewrites existing entries, so anything that still needs the old inline
style can edit `CHANGELOG.md` directly.
