# OnlyMacs Documentation Voice

When writing README files, website docs, launch copy, onboarding docs, or product explanations for OnlyMacs, do not default to terse engineering reference copy.

OnlyMacs documentation should feel:

- Clear, concrete, and technically trustworthy.
- Narrative-driven, not sterile.
- Founder-led and slightly cheeky, without becoming gimmicky.
- Written for smart Mac users, indie hackers, engineers, AI power users, and small teams who understand the pain of usage limits, hot laptops, cloud queues, and expensive idle hardware.
- More like a great open-source product README than an internal design doc.

## Core Positioning

OnlyMacs gives AI agents access to a swarm of Apple Silicon Macs - without subscription caps, token anxiety, or cloud GPU queues.

Do not frame the product as only "someone has an extra Mac Studio lying around." The stronger draw is that a user can give Codex, Claude Code, OpenCode, and terminal workflows access to the right Mac for the job: their own home army of Macs, a private swarm of trusted machines, or public remote Macs for work that is safe to send wide.

The setup promise:

Install the Mac app, keep using the agent tool you already like, and call `/onlymacs`. No model setup, no screen sharing, no SSH dance, and no figuring out which machine has enough memory before asking.

The emotional hook:

Your Macs are already powerful. Most of the day, they are doing nothing. OnlyMacs gives them a job.

The product metaphor:

A private AI swarm made out of Macs you already own or trust.

The default enemy:

- AI usage limits.
- Overheating your main laptop.
- Waiting on cloud queues.
- Paying again for compute you already bought.
- Sending private repo context to random remote services.
- Letting powerful Mac Studios and MacBook Pros sit idle.

## Writing Rules

Avoid generic AI-docs language:

- "streamline"
- "seamlessly"
- "leverage"
- "simple"
- "powerful"
- "robust"
- "AI-powered"
- "helps users"
- "enhance productivity"

Prefer concrete scenes:

- "Your MacBook stays cool while the Mac Studio in the other room handles the long review."
- "Send public docs work to the wider swarm. Keep private auth code on machines you trust."
- "Ask from Codex, Claude Code, or the terminal. Get back a result, a patch plan, or files in an inbox."

Every major section should answer:

1. What pain is this solving?
2. What does the user actually do?
3. What happens behind the scenes?
4. Why should they trust it?
5. What is the concrete example?

## README Style

The README should not start like a reference manual. It should start with:

1. A strong one-line promise.
2. A short narrative paragraph.
3. A concrete example command.
4. A short explanation of why this is different.
5. Then installation, usage, safety, repo structure, and contributor details.

Use headings that sound human:

- "Your Macs are bored"
- "The first command to try"
- "What should run where?"
- "How OnlyMacs keeps private work private"
- "What lives in this repo"
- "For contributors"

Do not bury the product story under implementation details.

## Use Case Quality Bar

Weak use case:

```sh
/onlymacs "review this README"
```

Better use case:

```sh
/onlymacs "send this public README to the swarm and return the three parts that would confuse a first-time user"
```

Weak use case:

```sh
/onlymacs "write docs"
```

Better use case:

```sh
/onlymacs "turn this rough install flow into a beginner-friendly setup guide, with warnings called out before users hit them"
```

Weak use case:

```sh
/onlymacs "review my diff"
```

Better use case:

```sh
/onlymacs go trusted-only "review my auth refactor on my trusted Macs only; call out security risks, missing tests, and anything that should not ship"
```

## Drafting Process

When asked to write or rewrite docs:

1. First identify the audience and the job of the document.
2. Create a short narrative outline.
3. Draft the copy with concrete examples.
4. Remove filler, corporate language, and vague claims.
5. Preserve technical accuracy.
6. Keep reference material, commands, paths, and build instructions exact.

Never produce a barebones README unless the user explicitly asks for a terse technical reference.
