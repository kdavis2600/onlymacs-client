"use client";

import { useEffect, useState } from "react";

const prompts = [
  "/onlymacs find launch blockers in this repo",
  "/onlymacs review this PR like senior QA",
  "/onlymacs --extended build the demo test pack",
  "/onlymacs --go-wide audit app, docs, and tests",
  "/onlymacs --plan:launch.md run the release plan",
];

export function Typewriter() {
  const [visibleText, setVisibleText] = useState("");

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const timeout = window.setTimeout(() => setVisibleText(prompts[0]), 0);
      return () => window.clearTimeout(timeout);
    }

    let promptIndex = 0;
    let charIndex = 0;
    let timeout: number;

    function typeNext() {
      const prompt = prompts[promptIndex];

      if (charIndex < prompt.length) {
        setVisibleText(prompt.slice(0, charIndex + 1));
        charIndex += 1;
        timeout = window.setTimeout(typeNext, 85);
        return;
      }

      timeout = window.setTimeout(() => {
        promptIndex = (promptIndex + 1) % prompts.length;
        charIndex = 0;
        setVisibleText("");
        typeNext();
      }, 1800);
    }

    typeNext();

    return () => window.clearTimeout(timeout);
  }, []);

  return (
    <>
      <span>{visibleText}</span>
      <span className="cursor" />
    </>
  );
}
