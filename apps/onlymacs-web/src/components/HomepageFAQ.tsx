import type { ReactNode } from "react";

type HomepageFAQItem = {
  answer: ReactNode;
  question: string;
  schemaAnswer: string;
};

type HomepageFAQGroup = {
  items: HomepageFAQItem[];
  label: string;
};

const faqGroups: HomepageFAQGroup[] = [
  {
    label: "Getting Started",
    items: [
      {
        question: "What is OnlyMacs in plain English?",
        answer: (
          <p>
            {
              "OnlyMacs turns the Macs you already own (and optionally a free public swarm) into a shared brain for getting work done. You can ask one Mac to do a small job, or ask your "
            }
            <strong>private swarm</strong>
            {
              " (your own trusted Macs) to tackle big tasks together. Or, if you're on a tight budget, use the "
            }
            <strong>public swarm</strong>
            {
              " (a free swarm of idle Macs) to run large batch jobs without paying for expensive API tokens. You type requests like "
            }
            <code>{'/onlymacs go local-first "explain this codebase"'}</code>
            {" -- or just "}
            <code>{'/onlymacs "explain..."'}</code>
            {
              " -- and the system figures out the best way to run it. Your data stays private because you control exactly what each swarm is allowed to see."
            }
          </p>
        ),
        schemaAnswer:
          'OnlyMacs turns the Macs you already own, and optionally a free public swarm, into a shared brain for getting work done. You can ask one Mac to do a small job, ask your private swarm of trusted Macs to tackle big tasks together, or use the public swarm to run large batch jobs without paying for expensive API tokens. You type requests like /onlymacs go local-first "explain this codebase" or just /onlymacs "explain..." and the system figures out the best way to run it. Your data stays private because you control exactly what each swarm is allowed to see.',
      },
      {
        question: "Why should I care? I already have ChatGPT.",
        answer: (
          <p>
            {
              "ChatGPT is great for public questions. But it's not designed for your private work, like reviewing internal strategy docs or fixing an unreleased app. OnlyMacs keeps sensitive work on your own Mac or inside your "
            }
            <strong>private swarm</strong>
            {
              ". And unlike pay-per-token services, the "
            }
            <strong>public swarm</strong>
            {
              " is free, so you can run massive jobs (think rewriting 10,000 files) without worrying about your monthly bill. You can even specify "
            }
            <code>{'/onlymacs go remote-first "generate 500 product descriptions"'}</code>
            {" to send a big non-sensitive job to the free swarm."}
          </p>
        ),
        schemaAnswer:
          'ChatGPT is useful for public questions, but OnlyMacs is designed for private work such as reviewing internal docs or fixing unreleased apps. OnlyMacs can keep sensitive work on your own Mac or inside your private swarm, and it can use the free public swarm for public-safe large jobs such as /onlymacs go remote-first "generate 500 product descriptions".',
      },
      {
        question: "I already have a 512GB Mac. Why do I need this?",
        answer: (
          <p>
            {
              "Because one Mac can be busy or underpowered for a large job. With OnlyMacs, that same Mac can ask another Mac you own (or the free public swarm) to do the heavy lifting while you keep using your main machine. Suddenly your 512GB Mac is even more useful: it can borrow power from the public swarm for batch work, or donate its own idle cycles to help others."
            }
          </p>
        ),
        schemaAnswer:
          "One Mac can be busy or underpowered for a large job. OnlyMacs lets that Mac ask another Mac you own, or the free public swarm for public-safe work, to do heavy lifting while you keep using your main machine.",
      },
      {
        question: "Is OnlyMacs hard to use for non-developers?",
        answer: (
          <p>
            {
              "Not at all. You install the app, keep it in your menu bar, and type plain English requests. For example: "
            }
            <code>{'/onlymacs go local-first "summarize the recent changes in this folder"'}</code>
            {" or "}
            <code>{'/onlymacs "review this document for security risks"'}</code>
            {
              " (the naked command works too). You don't need to write code. Most people are up and running in minutes."
            }
          </p>
        ),
        schemaAnswer:
          'OnlyMacs is designed for plain English requests from the menu bar app and assistant integrations. Examples include /onlymacs go local-first "summarize the recent changes in this folder" or /onlymacs "review this document for security risks". The naked command works too.',
      },
    ],
  },
  {
    label: "Everyday Use And Two Types Of Swarms",
    items: [
      {
        question: "What is the difference between a private swarm and the public swarm?",
        answer: (
          <ul>
            <li>
              <strong>Private swarm</strong>
              {
                " = Macs you or your team own and trust. They work together securely to solve complex problems fast. Great for private code reviews, confidential analysis, or any work that must never leave your hardware. You'd use "
              }
              <code>{'/onlymacs go trusted-only "audit the payment flow"'}</code>.
            </li>
            <li>
              <strong>Public swarm</strong>
              {
                " = A free, community-powered swarm of idle Macs. Anyone can use it for heavy, token-intensive jobs (like generating content or scanning thousands of public-safe files). Your data is safe when you control what the swarm can see and only approve public-safe input. Example: "
              }
              <code>
                {
                  '/onlymacs go remote-first "generate 200 unique product descriptions from this template"'
                }
              </code>.
            </li>
          </ul>
        ),
        schemaAnswer:
          'A private swarm is Macs you or your team own and trust, useful for private code reviews and confidential analysis. A public swarm is a free, community-powered swarm of idle Macs for heavy public-safe jobs. Examples include /onlymacs go trusted-only "audit the payment flow" and /onlymacs go remote-first "generate 200 unique product descriptions from this template".',
      },
      {
        question: "What kinds of things can I ask OnlyMacs to do?",
        answer: (
          <>
            <p>
              {
                "Almost anything involving reading, summarizing, or changing text or code. Examples:"
              }
            </p>
            <ul>
              <li>
                <code>{'/onlymacs go local-first "explain this unfamiliar codebase"'}</code>
                {" (private, local)"}
              </li>
              <li>
                <code>{'/onlymacs go remote-first "generate 100 SEO titles from these keywords"'}</code>
                {" (free public swarm)"}
              </li>
              <li>
                <code>{'/onlymacs go trusted-only "find duplicated patterns across the whole repo"'}</code>
                {" (private swarm)"}
              </li>
              <li>
                <code>{'/onlymacs "scan every markdown file and propose better titles"'}</code>
                {" (the system picks the best route automatically)"}
              </li>
            </ul>
            <p>
              {
                "The public swarm is amazing for large batch jobs where you don't want to pay per token."
              }
            </p>
          </>
        ),
        schemaAnswer:
          'OnlyMacs can read, summarize, or change text and code. Examples include /onlymacs go local-first "explain this unfamiliar codebase", /onlymacs go remote-first "generate 100 SEO titles from these keywords", /onlymacs go trusted-only "find duplicated patterns across the whole repo", and /onlymacs "scan every markdown file and propose better titles".',
      },
      {
        question: "Will it slow down my Mac?",
        answer: (
          <p>
            {
              "No. When you use the "
            }
            <strong>public swarm</strong>
            {" ("}
            <code>{"/onlymacs go remote-first ..."}</code>
            {
              "), the work happens on other people's idle Macs, so your machine does almost nothing. When you use your "
            }
            <strong>private swarm</strong>
            {" ("}
            <code>{"/onlymacs go trusted-only ..."}</code>
            {
              "), you can send heavy jobs to a desktop Mac while your laptop stays snappy. You can also set your Mac to stop sharing its own resources when on battery."
            }
          </p>
        ),
        schemaAnswer:
          "Using public swarm or trusted worker routes keeps most of the heavy work off your main Mac. Sharing your own Mac can use CPU, GPU, memory, and battery, but OnlyMacs lets you control when your Mac is eligible to help.",
      },
      {
        question: "Can I use OnlyMacs offline?",
        answer: (
          <p>
            {"Yes, if you stick to your "}
            <strong>private swarm</strong>
            {" and local models ("}
            <code>{"/onlymacs go local-first ..."}</code>
            {"). No internet needed."}
          </p>
        ),
        schemaAnswer:
          "OnlyMacs can be used offline for local-first work and local private swarm setups with local models.",
      },
    ],
  },
  {
    label: "Privacy And Security",
    items: [
      {
        question: "How does OnlyMacs protect my private data when using the public swarm?",
        answer: (
          <p>
            {
              "You stay in control. Before any job goes to the public swarm, you decide exactly what the swarm is allowed to read ("
            }
            <code>--context-read manual</code>
            {" or "}
            <code>git</code>
            {") and where results go ("}
            <code>inbox</code>
            {" or "}
            <code>staged</code>
            {
              "). The system can also warn, block, or apply secret-guard rules for sensitive patterns. You never have to send secrets or unrelated files. The public swarm is free, but you treat it like a public library -- you only give it the books you want to share."
            }
          </p>
        ),
        schemaAnswer:
          "OnlyMacs protects private data around public routes with explicit context approval, context read modes such as manual or git, reviewable outputs such as inbox or staged, and secret-guard policy. Users should only send public-safe material to the public swarm.",
      },
      {
        question: "What if I accidentally send sensitive data to the public swarm?",
        answer: (
          <p>
            {
              "OnlyMacs has guardrails. If your prompt mentions local files, internal code, or anything that looks sensitive, the system can block the request or warn you. You can also preview the route in the app before launching work. And you can always force the job to stay in your private swarm with "
            }
            <code>{"/onlymacs go trusted-only ..."}</code>.
          </p>
        ),
        schemaAnswer:
          "If a prompt mentions local files, internal code, or sensitive data, OnlyMacs can warn or block public routes. Users can keep work in their private swarm with /onlymacs go trusted-only or keep it local with local-first.",
      },
      {
        question: "Does OnlyMacs send my code to the cloud?",
        answer: (
          <p>
            {
              "Not unless you choose a route that does that. The "
            }
            <strong>public swarm</strong>
            {
              " uses other users' idle Macs -- not a centralized cloud. Your approved data is distributed among community machines for the job, but it is not meant to be stored or retained longer than needed. If that feels uncomfortable, just use your "
            }
            <strong>private swarm</strong>
            {" or "}
            <code>/onlymacs go local-first</code>
            {" to keep everything on your own devices."}
          </p>
        ),
        schemaAnswer:
          "OnlyMacs sends data based on route choice. local-first keeps work on This Mac, trusted-only uses approved Macs, and public-swarm or remote-first work sends approved public-safe input outside your trusted devices.",
      },
      {
        question: "Can I share my Mac's power without sharing my files?",
        answer: (
          <p>
            {
              "Absolutely. You can let your Mac join the "
            }
            <strong>public swarm</strong>
            {
              " to donate idle cycles, but you control exactly what files it can see via swarm-level policies and per-request approvals. Or you can keep your Mac in a "
            }
            <strong>private swarm</strong>
            {
              " with only your team. In both cases, file access is separate from compute donation."
            }
          </p>
        ),
        schemaAnswer:
          "OnlyMacs separates compute sharing from file access. A Mac can donate idle capacity without granting broad filesystem access, and file visibility is controlled through policy and per-request approvals.",
      },
    ],
  },
  {
    label: "Power And Performance",
    items: [
      {
        question: "Why would I want more than one Mac working together in a private swarm?",
        answer: (
          <p>
            {
              "For speed and privacy. Imagine you need to audit 10,000 files for security flaws. A private swarm of your own Macs (laptop + desktop + office mini) can split the work and finish faster than one machine. You'd run something like "
            }
            <code>{'/onlymacs --go-wide=4 go trusted-only "audit this codebase for risky patterns"'}</code>
            {
              ". Everything stays inside your hardware. Perfect for sensitive work."
            }
          </p>
        ),
        schemaAnswer:
          'More than one Mac helps with speed and privacy. A private swarm of trusted Macs can split broad reviews, docs passes, repo mapping, and test planning while keeping work inside trusted hardware. Example: /onlymacs --go-wide=4 go trusted-only "audit this codebase for risky patterns".',
      },
      {
        question: "What is the public swarm good for, and why is it free?",
        answer: (
          <>
            <p>
              {
                "The public swarm is ideal for "
              }
              <strong>large, non-sensitive batch jobs</strong>
              {" -- things like:"}
            </p>
            <ul>
              <li>
                <code>{'/onlymacs go remote-first "rewrite 500 blog posts to be more SEO-friendly"'}</code>
              </li>
              <li>
                <code>{'/onlymacs go remote-first "generate 10,000 alt-text descriptions for images"'}</code>
              </li>
              <li>
                <code>{'/onlymacs go remote-first "translate 1,000 support articles into Spanish"'}</code>
              </li>
            </ul>
            <p>
              {
                "It's free because users donate their Macs' idle time (like a volunteer compute grid). You don't pay per token, so you can run massive jobs without a budget. Just keep sensitive data offline or use your private swarm for that."
              }
            </p>
          </>
        ),
        schemaAnswer:
          "The public swarm is good for large non-sensitive batch jobs such as rewriting public blog posts, generating alt text, or translating public support articles. It is free because users donate idle Mac time, but sensitive data should stay local or in a private swarm.",
      },
      {
        question: "Will the public swarm be reliable for big jobs?",
        answer: (
          <p>
            {
              "It is designed for that. The coordinator splits your job into small tickets and distributes them across many idle Macs. If one Mac goes offline, the ticket can be reassigned. It's designed for burst-throughput batch processing. For time-critical work, your private swarm will be more predictable because the machines are dedicated to you."
            }
          </p>
        ),
        schemaAnswer:
          "The public swarm is designed for big public-safe jobs by splitting work into tickets and reassigning failed tickets. Public availability still varies, so private swarms are more predictable for time-critical work.",
      },
      {
        question: "Can I use the public swarm for coding work, like fixing all lint errors in a huge repo?",
        answer: (
          <p>
            {
              "Yes, if the repo and approved context are public-safe. Example: "
            }
            <code>
              {
                '/onlymacs --allow-tests go remote-first "review this open-source repo lint output and propose fixes"'
              }
            </code>
            {
              ". Each Mac in the public swarm can handle a different folder or file type when the job is split safely. The results come back as reviewable suggestions or patches that you review. It's like having a volunteer army of Macs clean up public code for free."
            }
          </p>
        ),
        schemaAnswer:
          'Public swarm coding work is appropriate when the repository and approved context are public-safe. Example: /onlymacs --allow-tests go remote-first "review this open-source repo lint output and propose fixes". Results should come back as reviewable suggestions or patches.',
      },
    ],
  },
  {
    label: "Example Use Cases",
    items: [
      {
        question: "I'm a writer. How can OnlyMacs help?",
        answer: (
          <ul>
            <li>
              <strong>Private swarm:</strong>{" "}
              <code>{'/onlymacs go trusted-only "review my manuscript draft for tone and clarity"'}</code>
              {" (confidential)."}
            </li>
            <li>
              <strong>Public swarm:</strong>{" "}
              <code>{'/onlymacs go remote-first "generate 200 variant headlines from my core ideas"'}</code>
              {" or "}
              <code>{'/onlymacs go remote-first "translate these 5 chapters into French"'}</code>
              {" -- all free, when the input is safe to share."}
            </li>
          </ul>
        ),
        schemaAnswer:
          'Writers can use a private swarm for confidential manuscript review, such as /onlymacs go trusted-only "review my manuscript draft for tone and clarity", and the public swarm for public-safe headline generation or translation.',
      },
      {
        question: "I manage a small team. Why would we use both swarms?",
        answer: (
          <ul>
            <li>
              <strong>Private swarm:</strong>{" "}
              <code>
                {
                  '/onlymacs go trusted-only "run the quarterly planning analysis on our internal docs"'
                }
              </code>
              {" (stays on your hardware)."}
            </li>
            <li>
              <strong>Public swarm:</strong>{" "}
              <code>
                {
                  '/onlymacs go remote-first "regenerate all our marketing collateral metadata and check for broken links across 10,000 pages"'
                }
              </code>
              {" -- zero token cost for public-safe work."}
            </li>
          </ul>
        ),
        schemaAnswer:
          "Small teams can use private swarms for internal docs and planning, and public swarms for public-safe marketing metadata or broken-link checks without token costs.",
      },
      {
        question: "Can the public swarm help with creative projects like game design?",
        answer: (
          <p>
            {"Yes. Example: "}
            <code>
              {
                '/onlymacs go remote-first "extract all character descriptions from these 500 design docs and classify them by role"'
              }
            </code>
            {" or "}
            <code>{'/onlymacs go remote-first "generate 1,000 lore-friendly item names"'}</code>
            {
              ". Because it's free, you can iterate many times without watching your spending. Keep unreleased or sensitive game IP in your private swarm unless you explicitly approve public-safe excerpts."
            }
          </p>
        ),
        schemaAnswer:
          "The public swarm can help with public-safe creative batch work such as classifying character descriptions or generating lore-friendly item names. Sensitive or unreleased game IP should stay in a private swarm unless public-safe excerpts are approved.",
      },
      {
        question: "I'm a student on a budget. Why should I use OnlyMacs?",
        answer: (
          <p>
            {"The "}
            <strong>public swarm</strong>
            {" gives you free compute for massive jobs: "}
            <code>{'/onlymacs go remote-first "summarize these 50 research papers into bullet points"'}</code>
            {", or "}
            <code>{'/onlymacs go remote-first "check my thesis for repeated phrases"'}</code>
            {
              ". And when you're working on something truly private (like your unpublished thesis), you use "
            }
            <code>{'/onlymacs go local-first "review this chapter"'}</code>
            {". Best of both worlds."}
          </p>
        ),
        schemaAnswer:
          "Students can use the public swarm for public-safe large jobs such as summaries or repeated-phrase checks, and local-first for private unpublished work.",
      },
    ],
  },
  {
    label: "Troubleshooting And Support",
    items: [
      {
        question: "What if a job in the public swarm fails mid-way?",
        answer: (
          <p>
            {
              "The public swarm is designed to retry failed tickets on other available Macs. You can also pause and resume large jobs. The coordinator keeps checkpoints, so you don't lose progress."
            }
          </p>
        ),
        schemaAnswer:
          "For public swarm jobs, the coordinator is designed to retry failed tickets on other available Macs, and larger jobs can be paused or resumed with checkpoints.",
      },
      {
        question: "How do I know if my private swarm Macs are talking to each other?",
        answer: (
          <p>
            {
              "Open the app and go to "
            }
            <strong>Swarms</strong>
            {
              ". You'll see every Mac in your private swarm and its status (online, offline, busy). For the public swarm, you just see that it's available -- you don't need to manage individual members."
            }
          </p>
        ),
        schemaAnswer:
          "Open the app and go to Swarms to see every Mac in your private swarm and its status. For the public swarm, users see whether it is available without managing individual members.",
      },
      {
        question: "Does OnlyMacs ever change my files without asking?",
        answer: (
          <p>
            {
              "Never. The default safe pattern is "
            }
            <code>inbox</code>
            {
              " -- results go to a draft folder. You review and apply them manually. For trusted workflows, you can use "
            }
            <code>staged</code>
            {" (Git staging area) or "}
            <code>direct</code>
            {
              " (only if you add the flag and your policy allows it). You are always the final reviewer."
            }
          </p>
        ),
        schemaAnswer:
          "OnlyMacs is designed around reviewable output. Results can go to an inbox, staged Git changes, or direct writes only when explicitly chosen and policy allows it. The user remains the final reviewer.",
      },
      {
        question: "Where can I get help if I'm stuck?",
        answer: (
          <p>
            {"Start with "}
            <code>/onlymacs check</code>
            {
              " in Claude Code or Codex -- it prints plain-English diagnostics. If you still need help, use the app's support bundle export or run "
            }
            <code>/onlymacs support-bundle latest</code>
            {
              " if support asks for a command. Secrets are redacted, but review the bundle before sharing it. The team and community are very responsive."
            }
          </p>
        ),
        schemaAnswer:
          "Start with /onlymacs check in Claude Code or Codex for plain-English diagnostics. If more help is needed, use the app support bundle export or /onlymacs support-bundle latest when support asks for a command, and review the bundle before sharing.",
      },
    ],
  },
];

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faqGroups.flatMap((group) =>
    group.items.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: item.schemaAnswer,
      },
    })),
  ),
};

export function HomepageFAQ() {
  return (
    <section className="homepage-faq" aria-labelledby="homepage-faq-title">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(faqJsonLd).replace(/</g, "\\u003c"),
        }}
      />

      <div className="faq-shell">
        <div className="faq-heading-row">
          <div>
            <p className="faq-kicker">Frequently Asked Questions</p>
            <h2 id="homepage-faq-title">Use your Macs without guessing the route.</h2>
          </div>
          <div className="faq-heading-copy">
            <p>
              Start with the plain command. Add a route word only when trust
              boundaries matter: <code>local-first</code> for This Mac,{" "}
              <code>trusted-only</code> for your Macs, and <code>remote-first</code>{" "}
              for public-safe work.
            </p>
          </div>
        </div>

        <div className="faq-grid">
          {faqGroups.map((group) => (
            <div className="faq-group" key={group.label}>
              <p className="faq-group-label">{group.label}</p>
              <div className="faq-stack">
                {group.items.map((item, index) => (
                  <details
                    className="faq-item"
                    itemScope
                    itemProp="mainEntity"
                    itemType="https://schema.org/Question"
                    key={item.question}
                    open={group.label === "Getting Started" && index === 0}
                  >
                    <summary>
                      <span itemProp="name">{item.question}</span>
                      <span className="faq-toggle" aria-hidden="true" />
                    </summary>
                    <div
                      className="faq-answer"
                      itemScope
                      itemProp="acceptedAnswer"
                      itemType="https://schema.org/Answer"
                    >
                      <div itemProp="text">{item.answer}</div>
                    </div>
                  </details>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
