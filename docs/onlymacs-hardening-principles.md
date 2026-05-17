# OnlyMacs Hardening Principles

These principles are the guardrails for improving `/onlymacs` without turning it into a pile of one-off prompt hacks.

## 1. Fix classes of failure, not single prompts

When a scenario fails, identify the broader failure mode first. Keep the exact scenario as a regression test, but fix the shared cause.

## 2. Keep the skill thin

The skill should stay a lightweight front door. Core behavior belongs in the launcher, policy layer, app approval/export path, and runtime contracts.

## 3. Route by structured intent, not surface wording alone

Classify requests by task kind, file need, write intent, sensitivity, and route safety. Prompt wording matters, but it should not be the only decision input.

## 4. Require command-like phrasing for control commands

Session controls such as `stop`, `pause`, `resume`, and `watch` should only trigger when the request actually looks like a command. Normal prose must not trip them accidentally.

## 5. Enforce public, private, and local behavior structurally

Do not rely on advisory text alone. Public swarms must block file access, private swarms must require approval, and local-only recommendations must be enforced in behavior.

## 6. Fail honestly when a capability is missing

If `/onlymacs` cannot safely complete a class of request yet, stop clearly and explain why. Do not silently downgrade into a generic answer that looks more capable than it is.

## 7. Make task contracts explicit

Different task families need different output shapes. Reviews, code reviews, generation, and transforms should each have their own required sections and grounding rules.

## 8. Require evidence for material claims

The system should prefer a smaller number of grounded claims over a larger number of vague ones. Reviews should cite approved files and, where possible, line-aware evidence.

## 9. Weight better evidence higher

Not all approved files are equal. Source, config, schema, and core docs should outrank readme-style overview material when the task depends on stronger proof.

## 10. Prefer fewer full files over many weak fragments

For review-grade work, a small full-context bundle is usually more reliable than a broad but trimmed export. Do not fake comprehensive review from partial scraps.

## 11. Make file approval readable and auditable

Users should see what is being shared, why it was selected, and what will leave the Mac. The manifest, selection UI, and audit trail are part of product trust, not just tooling.

## 12. Let the app and launcher agree on one policy truth

The launcher, bridge, app, and QA harness should all rely on the same request-policy model. Parallel heuristics drift quickly and create contradictory behavior.

## 13. Turn every real bug into an automated check

Every meaningful production failure should become either a unit test, a launcher smoke test, a matrix scenario, or an autonomous UI regression. That is how hardening compounds.

## 14. Optimize for friend-facing clarity, not internal cleverness

When behavior is ambiguous, choose the path that is easiest to explain to a normal user. If a route, block, or approval step feels confusing in plain English, the product is not done.

## 15. Grow coverage in layers

Add coverage in this order:

1. policy corpus
2. launcher smoke tests
3. live scenario matrix
4. autonomous UI flow

That keeps the system testable while still pushing toward realistic end-to-end confidence.

## 16. Isolate maintenance from serving

Model downloads, model imports, app updates, and other maintenance work must not interrupt an active remote job. If a Mac is installing or downloading a model, expose that as a separate member state and keep any already assigned serving slot stable until the current job finishes, fails, or is intentionally cancelled.
