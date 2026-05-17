# Mac-First Host Supply Strategy

My take: keep OnlyMacs Mac-first. The PC supply side is real, but it is much more "hardcore hobbyist / workstation owner" than "normal person with a decent laptop."

The key distinction is:

- 64GB/128GB system RAM on a PC is common-ish and affordable.
- 64GB/128GB VRAM on a PC is rare and expensive.

On Apple Silicon, the GPU can use Apple's unified memory pool, so a 64GB or 128GB MacBook Pro/Mac Studio can run larger local models than a normal laptop with a separate GPU. Apple's current M5 Max MacBook Pro supports up to 128GB unified memory, and the 40-core GPU version has 614GB/s memory bandwidth.

## Rough Cost Equivalence

| Host type | Practical AI memory | Approx cost / reality | OnlyMacs value |
| --- | --- | --- | --- |
| 64GB MacBook Pro M5 Max | Large shared memory pool | Around $4.6k list for a 16-inch M5 Max 64GB/2TB config, based on current retail/deal listings. | Very strong |
| 128GB MacBook Pro M5 Max | Very large shared memory pool | Around $5.4k-$6k for 128GB configs depending on storage. | Excellent |
| High-end gaming laptop PC | Usually 8-24GB VRAM | Even top RTX 5090 laptop GPUs top out around 24GB VRAM, not 64/128GB. | Useful for small/medium jobs only |
| RTX 5090 desktop | 32GB VRAM | NVIDIA lists RTX 5090 as 32GB GDDR7, starting at $1,999 before the rest of the PC. | Very fast, but memory-limited |
| 2x RTX 5090 desktop | 64GB total VRAM, split across GPUs | At least ~$4k GPU MSRP alone, realistically much more with full rig/power/cooling; model splitting required. | Great but rare/hardcore |
| RTX 6000 Ada workstation GPU | 48GB VRAM | NVIDIA's pro card has 48GB GDDR6. | Great, but workstation niche |
| RTX PRO 6000 Blackwell | 96GB VRAM | Listed around $8,565 in U.S. reporting; Vietnamese listings show much higher local retail. | Amazing, but not casual |
| AMD Radeon Pro W7900 | 48GB VRAM | Roughly $3.4k-$3.5k class, but AMD/ROCm support is more friction than NVIDIA CUDA for many AI stacks. | Interesting later |

## The Practical Model-Hosting Difference

For LLMs, the math is brutal. A 70B model at 4-bit quantization is roughly 35GB just for weights, then you still need overhead and context/KV cache. So:

RTX 4090 / 5090 class PCs are insanely fast, but 24-32GB VRAM is often too small for the same model class a 64GB/128GB Apple Silicon Mac can host.

That is why a 128GB MacBook Pro is weirdly attractive for local AI: not because it beats a 5090 on raw speed, but because it can fit models that consumer GPUs often cannot fit cleanly.

## Prevalence: PC Hosts Are Probably Not Your Mainstream Supply

Steam's March 2026 hardware survey is not the whole PC market, but it is a decent proxy for enthusiast machines. Even there, 24GB VRAM is only 4.84%, 32GB VRAM is 1.18%, and "Other" is 1.77%; common VRAM buckets are still 8GB, 12GB, and 16GB.

Specific high-end cards are also small-share: RTX 4090 appears at 0.74%, RTX 5090 at 0.40%, and RTX 3090 at 0.40% in that survey.

So the answer to your core question is:

Normal PC owners are probably not great OnlyMacs hosts. Hardcore PC gamers, AI hobbyists, and workstation owners are.

## What This Means For OnlyMacs

I would segment it like this:

**Mac hosts:**

Your cleanest supply. A lot of developers, creators, and founders already have M-series Macs sitting idle. A 32GB Mac is useful. A 64GB Mac is very useful. A 128GB Mac is genuinely valuable.

**Consumer PC hosts:**

Mostly useful for smaller jobs: embeddings, code agents, small local models, image tasks, transcription, batch jobs, maybe 7B-34B LLMs depending on GPU. But most non-hardcore PCs are not "big model hosts."

**Hardcore PC hosts:**

Very valuable, but niche. RTX 3090/4090/5090 owners, multi-GPU rigs, Linux AI boxes, workstation cards. These people may join, but they are closer to "AI homelab" users than casual idle-computer users.

**Enterprise/workstation PC hosts:**

Technically excellent, but they probably already understand the value of their hardware. Harder to acquire casually.

## Strategic Recommendation

I would not rebrand away from OnlyMacs early. The name is actually part of the thesis:

"Apple Silicon made high-memory local AI weirdly mainstream."

That is much more distinctive than "idle computers for AI," which sounds like every distributed compute marketplace.

Later, you can support PCs under the hood and position it like:

OnlyMacs - Mac-first local AI swarms. Now with experimental PC workers.

Or:

OnlyMacs runs best on Apple Silicon, and also supports high-VRAM PCs.

The killer wedge is still Mac. PCs become a power-user expansion, not the original identity.
