# Public Client Publication Checklist

Use this checklist before publishing a public client repo export. The current working tree is split, but the private working repo history still contains private service source from before the split.

## Current layout

- Client repo: this repository.
- Hosted coordination service: maintained outside the public client repo.
- Public client validation should not require private service source.

## Before Publishing The Client Repo

1. Keep the current origin private while product work continues.
2. Publish under Apache-2.0, using the root `LICENSE` file in this repo.
3. Publish from a clean public export, not by flipping this repository public with its full existing history.
4. Prefer creating a new public repo from a fresh checkout of the post-split tree. If preserving history is required, filter the history first and verify private service paths are gone from every commit.
5. To create a local fresh-history export without creating a public repo yet, run:

```bash
make public-export
```

By default, this writes a new one-commit Git repository to `.tmp/onlymacs-public-client-export` and runs the public preflight there without private-history overrides.

6. When you are ready to publish, add the empty public remote from inside that export directory and push its `main` branch.
7. Keep docs repository links disabled until the target public repo exists and is intentionally public.
8. Keep public CI independent of the private service repo. Managed-service tests should stay outside public client CI.
9. Keep local agent/plugin workspaces out of the public tree. The repo ignores `.codex/`, `.agents/`, `.claude/`, `.windsurf/`, and local skill archives by default.
10. Run the public client preflight before export. In this private working repo, the history check is expected to warn or fail until a fresh public export or filtered history exists:

```bash
ONLYMACS_ALLOW_PRIVATE_HISTORY=1 make public-preflight
```

Run the same command without the override in the final public export.

11. Run targeted text scans before public release:

```bash
OLD_PRIVATE_SERVICE_PATH="$(printf 'services/%s' coordinator)"
PRIVATE_REPO_URL="github.com/<owner>/<private-client-repo>"
DOC_PROJECT_LABEL="$(printf 'Project %s' repository)"
DOC_EDIT_LABEL="$(printf 'Improve %s page' this)"
DOC_FEEDBACK_LABEL="$(printf 'Was this page %s' clear?)"
rg -n -e "$OLD_PRIVATE_SERVICE_PATH" -e "OnlyMacs/$OLD_PRIVATE_SERVICE_PATH" -e "$PRIVATE_REPO_URL" -e "$DOC_PROJECT_LABEL" -e "$DOC_EDIT_LABEL" -e "$DOC_FEEDBACK_LABEL" .
git log --all -- "$OLD_PRIVATE_SERVICE_PATH"
```

The first command should return nothing in the public export. The second command should return nothing only after using a fresh public repo or a filtered history.
