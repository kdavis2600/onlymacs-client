# OnlyMacs For Humans

## Turn Idle Macs Into A Private AI Fleet

One app. One menu bar icon. One branded command surface. A whole lot fewer paid tokens.

OnlyMacs is the product for people who want the magic version:

- download one DMG
- drag one app into `Applications`
- click one big `Make OnlyMacs Ready` button
- open `Codex` or `Claude Code`
- type `/onlymacs ...`
- watch your own Mac and trusted Macs light up like a private AI fleet

This document describes the finished experience we are building toward.

If we ship anything worse than this, we shipped too early.

## What OnlyMacs Is

OnlyMacs is one macOS menu bar app with three modes:

- `Use remote Macs`
- `Share this Mac`
- `Both`

That means:

- you can borrow model capacity from your own Macs or trusted people
- you can lend your Mac back when it is idle
- you can keep `Codex` or `Claude Code` as the local orchestrator
- you can save serious money by offloading work to Macs you already trust before you pay for more cloud tokens

OnlyMacs is not trying to replace your coding tool.

It is trying to make local, remote, and hybrid AI work feel unfairly easy.

## The Big Promise

OnlyMacs should feel like this:

> "I installed one app, joined one private swarm, typed one command in Codex, and suddenly I had a swarm."

And the second promise is just as important:

> "I stopped lighting money on fire for cloud tokens when my own Macs and my friends' Macs could do the work first."

## What Makes It Feel Like Magic

OnlyMacs is at its best when it hides the nonsense and shows the truth.

It should:

- install and repair the Codex and Claude integrations for you
- show exact model names instead of mysterious marketing aliases
- pick the best open model it can justify
- explain when it had to queue, clamp, or downgrade
- track your recent swarms so you do not lose work
- let you share or join a swarm with one invite link or QR code
- show how many tokens you saved by staying inside OnlyMacs capacity
- make the whole thing feel like software, not a research project

## The 60-Second Setup

### If you want to use remote Macs

1. Open `OnlyMacs.app`
2. Choose `Use remote Macs`
3. Enter a display name
4. Leave `Launch at Login` on
5. Click `Make OnlyMacs Ready`
6. Let OnlyMacs:
   - install or repair the `/onlymacs` launcher for Codex and Claude
   - open or relaunch the right tool if needed
   - run a preflight check
   - show `Ready`
7. Join a private swarm by invite link, QR code, or backup code

### If you want to share your Mac

1. Open `OnlyMacs.app`
2. Choose `Share this Mac`
3. Enter a display name
4. Leave `Launch at Login` on
5. Pick one recommended model and any additional exact models you want to offer
6. Click `Make OnlyMacs Ready`
7. Let OnlyMacs:
   - start the local runtime
   - download the selected models
   - warm them up
   - benchmark safe slot capacity
   - mark your Mac `Ready`
8. Share your private swarm invite

The app should be opinionated here.
A 32GB-class host should not see the same prechecked downloads as a 256GB-class host.
OnlyMacs should use its local curated catalog to offer the right exact models for the machine it is running on.
On bigger machines, that can mean a recommended bundle instead of just one model, as long as the app shows the total size, estimated time, and keeps a healthy free-space reserve.
Each model should download one at a time and come online as soon as it is ready, instead of making the user wait for the whole bundle to finish.

### If you want both

1. Choose `Both`
2. Let OnlyMacs start conservatively
3. Use remote Macs first
4. Let sharing ramp up only after the app proves your Mac can safely do both

No shell profile edits.
No port numbers.
No guessing where the scripts live.
No "go read the docs and come back later."

## Joining A Swarm Should Feel Ridiculously Easy

OnlyMacs should support:

- `Share Invite`
- `Copy Link`
- `Scan QR`
- `Open Invite Link`
- `Enter Backup Code`

The ideal flow is dead simple:

1. Someone creates a private swarm
2. They send you a secret invite link
3. You click it
4. OnlyMacs opens
5. You join
6. You immediately see the swarm roster, available models, and open slots

Private by default.
Simple by default.
No LAN spelunking.
No IP addresses.

## Your Menu Bar Should Tell The Truth Fast

When you click the OnlyMacs menu bar icon in `Use` or `Both` mode, the top of the menu should immediately show:

- `Support / Donate`
- `Tokens Saved`

Then it should show the real operational stuff:

- swarm name
- total free slots
- active sessions
- recent sessions
- exact model availability
- progress state
- route type: local, remote, or hybrid
- `Community Boost`

If you are sharing, the menu should also show:

- share on/off
- installed models
- free and used slots
- tokens per second while active
- session totals
- energy estimate
- who is currently using capacity without exposing private prompt content

If you are doing both, it should also tell you:

- whether `This Mac` is currently eligible
- whether local load is suppressing future share slots
- whether your current swarm is local-first, remote-first, or mixed

## The Only Command People Should Need To Learn

The brand has to live where the work starts.

That means the user-facing command surface should be:

```bash
/onlymacs ...
```

Not random helper scripts.
Not buried wrappers.
Not a file path copied out of a README.

### The core verbs

```bash
/onlymacs "do a code review on my project"
/onlymacs go balanced "review this patch and list the top 5 risks"
/onlymacs go wide 4 "break this refactor into parallel workstreams"
/onlymacs go offload-max "summarize this repo without burning cloud tokens"
/onlymacs watch latest
/onlymacs status latest
/onlymacs pause latest
/onlymacs resume latest
/onlymacs stop latest
```

### What `go` should do automatically

When a user types `/onlymacs go ...`, the product should quietly handle the hard parts:

- run a hidden preflight
- resolve exact model availability
- clamp to safe width
- decide whether the request should start, queue, or ask for confirmation
- attach the user to the resulting session
- explain any important decision in plain English

The wrapper should feel like a helpful guide, not a bouncer guarding an API.

## How OnlyMacs Should Pick Models

OnlyMacs should not pick the first random idle machine.

It should pick like it has taste.

### `best available` means:

- the strongest eligible exact model with an open slot right now
- subject to route policy, safety, context fit, and current capacity
- with provider hardware and throughput used only as secondary tiebreakers

If someone in the swarm has a 256GB Mac Studio with a monster coding model and an open slot, that machine should usually win.

If that rare capacity is contested, `Community Boost` can act as a small tiebreaker.

Small.
Not tyrannical.
Not a caste system.

### The quality controls should stay human-readable

- `quick`: give me a fast strong answer
- `balanced`: give me the best default
- `precise`: prefer the strongest model and wait briefly if needed
- `offload-max`: keep this inside OnlyMacs capacity first so I save money
- exact model: use this model and do not pretend a weaker one is "basically the same"

### The app should always explain the decision

Examples:

- `Qwen 32B started because a premium slot was open.`
- `Qwen 14B started because all open 32B slots were busy.`
- `Waiting for Qwen 32B because you asked for exact model continuity.`

That is what trust looks like.

## Premium Capacity: How The Rare Good Stuff Should Work

If ten people want the one legendary Mac Studio, the system needs rules.

Here are the right ones.

### A premium slot belongs to an active session, not a single curl call

Users should never have to predict how many underlying inference calls their work will make.

OnlyMacs should treat the scarce slot as belonging to the active session or sub-agent while that work is still progressing.

### Active work keeps the slot

If your premium session is actively moving, it should keep its slot.

Nobody should be able to steal it mid-run just because they clicked later and want the same premium model.

### Idle work does not hold the slot forever

If the session goes idle for a short window, roughly `60-120s`, the lease can expire.

Manual pause should release it immediately.

### Resume should be honest

If you come back later and the premium model is no longer open, OnlyMacs should say so plainly:

- `Wait for same model`
- `Use best available now`
- `Use local if possible`
- `Cancel`

No silent downgrade.
No false reservation fantasy.

### The queue should mostly be event-driven

When premium capacity opens up, the app should know because the swarm changed, not because it mindlessly woke up every few minutes and guessed.

Polling is an acceptable backup.
It should not be the brains of the system.

## Three Killer First Use Cases

These are the kinds of jobs that make people immediately understand why OnlyMacs exists.

### 1. Review a patch fast

```bash
/onlymacs go balanced "review this patch and tell me the riskiest changes first"
```

Why it is good:

- easy to judge
- easy to compare models
- perfect for a first swarm

What you should see:

- admitted width
- resolved model
- running progress
- final summary in Codex or Claude

### 2. Break down a nasty refactor

```bash
/onlymacs go wide 4 "split this refactor into parallel workstreams with risks and dependencies"
```

Why it is good:

- benefits from several parallel reasoning passes
- makes queueing obvious
- shows the swarm value immediately

What you should see:

- requested vs admitted width
- queue state for any remainder
- a combined final plan

### 3. Save money on a heavy repo read

```bash
/onlymacs go offload-max "read this repo and propose a migration plan"
```

Why it is good:

- proves the token-saving story
- proves local-plus-trusted-swarm routing
- makes `Tokens Saved` feel real

What you should see:

- whether the job stayed inside OnlyMacs capacity
- whether local or remote Macs did the work
- how many tokens you avoided burning in paid cloud paths

## How To Track Progress Without Guessing

OnlyMacs should make progress visible in both places that matter:

### In the app

You should be able to see:

- `Queued`
- `Running`
- `Paused`
- `Completed`
- `Failed`

And for each session:

- title
- exact model
- requested width
- admitted width
- active providers
- queue reason
- rough ETA when honest
- route type

### In Codex or Claude

You should be able to say:

```bash
/onlymacs watch latest
/onlymacs status latest
/onlymacs resume latest
```

### What "done" should mean

A session is done when:

1. the bridge marks it `Completed`
2. the app shows it completed
3. the orchestrator has the final answer or summary

If those disagree, the product should treat that as a bug.

## How OnlyMacs Saves People Money

This is not a side quest.
It is one of the main reasons the product matters.

OnlyMacs should:

- prefer local and trusted-swarm capacity before paid cloud paths when the user asks for it
- make `offload-max` a first-class route policy
- show a visible `Tokens Saved` number in the app
- explain when a request stayed inside OnlyMacs capacity
- explain when it could not

The point is not fake financial precision.

The point is momentum.

People should feel:

> "This thing is saving me real money because it keeps finding work for Macs I already own or trust."

## What Sharers Need To Understand

OnlyMacs should not force sharers to become hobbyist infra operators.

Sharers should only need to understand:

- which exact models they want to offer
- how many safe slots their Mac can support
- whether they want equal access or mild preference for stronger contributors on rare premium slots
- whether their Mac should prioritize local comfort or maximum sharing

Everything else should feel automatic.

There are two different ways to become a star in the swarm, and both should matter:

- be the **Backbone Mac**: always on, healthy, available, and constantly useful
- be the **Heavy Hitter**: rare hardware, rare models, rare capacity that other people cannot easily offer

The right product rewards both.
It should not pretend that only raw historical tokens matter, and it should not pretend that premium hardware with zero generosity deserves the whole world either.

A brand-new premium host should get some early respect, but not instant monarchy.
The fair version is:

- verified premium capability gives you a provisional boost
- real uptime and real served work turn that boost into durable status
- rare models help you climb faster, but they do not erase the need to actually show up and serve

If a sharer installs more models, the app should say plainly:

> "The more exact models you install, the more requests your Mac can satisfy."

That is enough.

## The Version Of "Both" That Deserves To Exist

`Both` is only good if it is honest.

That means:

- your local experience wins
- dangerous overcommit is prevented
- future share slots shrink before your Mac becomes miserable
- `This Mac` can still help your own swarm when safe
- sharing does not turn your machine into a toaster oven

If `Both` feels reckless, it is not done.

## The Questions Smart Skeptics Will Ask

### "Is this a real product or a local toy?"

It should be a real private-swarm product with coordinator-managed invites, routing, session state, and local fallback when appropriate.

### "Can remote Macs run my tools?"

No.
Remote Macs provide inference.
Tool execution stays requester-side.

### "Do you hide models behind vague names?"

No.
Exact model names stay visible.
Helpful hints can sit on top, but the truth stays on the screen.

### "Can I force local-only, remote-only, or hybrid?"

Yes.
The route policy should be explicit.

### "Can I insist on one exact premium model?"

Yes.
And if it is busy later, OnlyMacs should wait, explain, or let you fall back intentionally.

### "What stops one thread from chewing through the whole swarm?"

Workspace and thread-aware admission caps, idempotency, queueing, and clamp reasons.

### "What happens if a provider disappears?"

Checkpoint partial work, explain what happened, and resume or fail honestly according to policy.

### "Can multiple people use the same swarm?"

Yes.
That is the point of private invite-only swarms.

### "Do I need Terminal to use this?"

No.
Not in the version worth shipping.

### "Do I need to memorize different commands for Codex and Claude?"

No.
The product should teach one surface:

```bash
/onlymacs ...
```

### "Will it tell me what actually happened?"

It had better.

Model used.
Queue reason.
Why it clamped.
Why it waited.
Why it fell back.
Why it saved you money.

If it cannot explain itself, it is not ready.

## What Great Looks Like

The finished OnlyMacs experience should feel almost suspiciously smooth:

- download one app
- join one private swarm
- click `Make OnlyMacs Ready`
- type one `/onlymacs` command
- watch the app and your orchestrator stay in sync
- finish real work
- save real tokens

That is the bar.

## What We Should Refuse To Ship

Do not ship a version that requires normal users to:

- edit shell profiles
- find script paths manually
- guess whether a job ran locally or remotely
- lose a session because they closed a terminal
- read raw logs to understand queueing
- learn different command vocabularies for Codex and Claude
- wonder which model actually answered
- wonder whether they saved money or just hoped they did

If the product demands any of that, the product is not ready.

## The Rallying Cry

OnlyMacs should feel like this:

> Your Macs. Your friends' Macs. Your models. Your swarm. Your savings.

Not:

> Congratulations, you are now the unpaid IT department for your own AI tooling.

That is the vision.
That is the standard.
That is what we are building.
