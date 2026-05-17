import type { ReactNode } from "react";

type BlockProps = {
  children: ReactNode;
  title?: string;
};

type CalloutProps = BlockProps & {
  tone?: "default" | "good" | "warn" | "example";
};

export function Learn({ children, title = "What you'll learn" }: BlockProps) {
  return (
    <section className="om-doc-learn" aria-label={title}>
      <p className="om-doc-kicker">{title}</p>
      <div>{children}</div>
    </section>
  );
}

export function BestDefault({ children, title = "Best default" }: BlockProps) {
  return (
    <Callout tone="good" title={title}>
      {children}
    </Callout>
  );
}

export function Avoid({ children, title = "What to avoid" }: BlockProps) {
  return (
    <Callout tone="warn" title={title}>
      {children}
    </Callout>
  );
}

export function Example({ children, title = "Example" }: BlockProps) {
  return (
    <Callout tone="example" title={title}>
      {children}
    </Callout>
  );
}

export function Note({ children, title = "Note" }: BlockProps) {
  return (
    <Callout title={title}>
      {children}
    </Callout>
  );
}

export function Troubleshooting({
  children,
  title = "Troubleshooting",
}: BlockProps) {
  return (
    <Callout tone="warn" title={title}>
      {children}
    </Callout>
  );
}

export function NextStep({ children, title = "Go next" }: BlockProps) {
  return (
    <section className="om-doc-next" aria-label={title}>
      <p className="om-doc-kicker">{title}</p>
      <div>{children}</div>
    </section>
  );
}

export function Recipe({ children, title = "Recipe" }: BlockProps) {
  return (
    <section className="om-doc-recipe" aria-label={title}>
      <p className="om-doc-kicker">{title}</p>
      <div>{children}</div>
    </section>
  );
}

export function Decision({ children, title = "Decision guide" }: BlockProps) {
  return (
    <section className="om-doc-decision" aria-label={title}>
      <p className="om-doc-kicker">{title}</p>
      <div>{children}</div>
    </section>
  );
}

function Callout({ children, title = "Note", tone = "default" }: CalloutProps) {
  return (
    <aside className={`om-doc-callout om-doc-callout-${tone}`}>
      <p className="om-doc-callout-title">{title}</p>
      <div>{children}</div>
    </aside>
  );
}
