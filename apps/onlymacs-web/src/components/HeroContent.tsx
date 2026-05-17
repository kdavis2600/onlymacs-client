const specs = [
  ["Install Time", "30 seconds"],
  ["Technical Knowledge", "None required"],
  ["Est. Free Tokens", "1M+ Tokens per day"],
  ["Models Supported", "16 Models"],
];

export function HeroContent() {
  return (
    <section className="content-col" aria-labelledby="landing-title">
      <h1 id="landing-title">
        <span>Imagine a</span>
        <span>
          world <em>without</em>
        </span>
        <span>usage limits...</span>
      </h1>
      <p className="lead">
        OnlyMacs turns idle Apple Silicon into free AI compute for agents,
        local models, and coding tools — without subscription caps, token
        anxiety, or cloud GPU queues.
      </p>

      <div className="cta-group">
        <a
          aria-label="Join the OnlyMacs waitlist"
          className="btn"
          href="/waitlist/join"
        >
          Join Waitlist
        </a>
        <a
          aria-label="Redeem an OnlyMacs invite code"
          className="price-tag invite-link"
          href="/redeem"
        >
          I have an invite code
        </a>
      </div>

      <div className="specs-grid" aria-label="Product specifications">
        {specs.map(([label, value]) => (
          <div className="spec-item" key={label}>
            <h4>{label}</h4>
            <p>{value}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
