# Trusted Swarm File Access QA Checklist

This checklist is the "what mistakes could I have made?" sweep for the current trusted file-access implementation.

Status keys:

- `PASS` means the check was covered in automated validation during this pass.
- `MANUAL` means the current pass could not prove it without live desktop interaction.
- `BLOCKED` means the underlying product or environment still lacks the capability.

## Launcher and request policy

1. `PASS` Public swarm file-aware requests are blocked.
2. `PASS` Private swarm file-aware requests require approval.
3. `PASS` Local-only requests do not require private export approval.
4. `PASS` Route classification still handles plain prompt-only requests.
5. `PASS` Route classification still handles wide/plan/go requests.
6. `PASS` Explicit route overrides still win over suggested routing.
7. `PASS` The launcher explains why a route was chosen.
8. `PASS` Same prompt with a different approved bundle changes the idempotency key.
9. `PASS` The launcher stops if the approval bundle is missing.
10. `PASS` The launcher no longer rewrites the prompt with `context.txt` for trusted file access.

## Approval and export safety

11. `PASS` The approval flow writes a manifest.
12. `PASS` The approval flow writes a bundle.
13. `PASS` Obvious secret file paths like `.env` are blocked.
14. `PASS` Obvious credential-like file contents are blocked.
15. `PASS` Non-text files are blocked from trusted export.
16. `PASS` Selected files preserve a stable preview status (`ready`, `trimmed`, `blocked`, `missing`).
17. `PASS` Review-mode exports block oversized core files instead of silently trimming them.
18. `PASS` Smaller trusted-context exports may still trim supporting files when allowed.
19. `PASS` The export manifest records per-file byte counts and SHA data.
20. `PASS` Approval and rejection both write explicit response artifacts.

## Artifact transport

21. `PASS` Approved bundles are serialized into launcher payloads.
22. `PASS` Chat payloads carry the artifact when present.
23. `PASS` Swarm plan payloads carry the artifact when present.
24. `PASS` Swarm start payloads carry the artifact when present.
25. `PASS` The bridge accepts artifact metadata on chat requests.
26. `PASS` The bridge accepts artifact metadata on swarm requests.
27. `PASS` Artifact bytes are included in request token estimation.
28. `PASS` Artifact bytes are included in swarm context budgeting.
29. `PASS` Swarm sessions preserve artifact metadata for execution.
30. `PASS` Resumed swarm sessions preserve artifact metadata.

## Execution path

31. `PASS` Local inference strips the artifact before upstream model execution.
32. `PASS` Local inference hydrates approved file contents into the request context.
33. `PASS` Remote relay workers strip the artifact before upstream model execution.
34. `PASS` Remote relay workers hydrate approved file contents into the request context.
35. `PASS` Swarm execution requests preserve artifact metadata until execution time.
36. `PASS` Extracted bundles are staged in a temporary workspace.
37. `PASS` Bundle SHA verification is enforced when a checksum is present.
38. `PASS` Tar extraction rejects invalid or escaping paths.
39. `PASS` Unsupported tar entry types fail closed.
40. `PASS` Temporary artifact workspaces are cleaned up after inference.

## UI and user-facing behavior

41. `PASS` The approval window keeps long filenames and paths inside the visible bounds.
42. `PASS` The right-column warning area wraps instead of clipping one-line labels.
43. `PASS` Pipeline-doc prompts prioritize the master docs and README files above stale run artifacts.
44. `PASS` Recommended files are preselected instead of taking the first arbitrary files.
45. `PASS` Deprecated run manifests and notes are no longer top-priority picks for pipeline-doc review prompts.
46. `PASS` The approval window appears only once per request on the live desktop.
47. `PASS` The approval window closes cleanly on the first user attempt.
48. `PASS` The approval window comes to the front on a live Codex-triggered request.
49. `MANUAL` The live Codex request resumes automatically after approval.
50. `PASS` Trusted staged bundles can run through remote Codex or Claude Code execution instead of always flattening back into prompt context.
