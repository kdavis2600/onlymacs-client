# AGENTS.md

## Repository Instruction Routing

- Follow `CODEX.md` before non-trivial OnlyMacs work; it holds the detailed local Codex guidance for this repository.
- Keep this file small. It is startup context, not a project notebook.
- Put solved setup, build, test, and environment failures in `docs/troubleshooting.md`.
- Put durable repo-wide conventions and debugging shortcuts in `docs/codex-learnings.md`.
- Put folder-specific conventions in the closest relevant `README.md`.

## Continuous Learning Protocol

At the end of a task, consider whether the work revealed a durable learning worth preserving.

Do not document ordinary implementation details, task logs, obvious code behavior, one-off temporary fixes, low-confidence guesses, or facts already clear from nearby code.

Good learning candidates usually satisfy at least three:

- A bug, build failure, dependency issue, test issue, or environment issue was encountered and solved.
- The solution required non-obvious investigation or reading multiple files.
- Codex made a wrong assumption about the project and corrected it.
- A repo-specific convention, command, workflow, config, or file location was discovered.
- The same explanation would likely save future debugging or reduce repeated file-reading.

Before adding a learning:

1. Search existing docs for a similar entry.
2. Prefer tightening or merging an existing entry over adding a duplicate.
3. Keep the entry short and concrete.
4. Include the trigger, root cause, fix, and future shortcut when documenting failures.
5. Delete or rewrite stale/conflicting learning when discovered.

Token budget rule: a learning should earn its place. If it will not likely save at least 5 minutes later, skip it.
