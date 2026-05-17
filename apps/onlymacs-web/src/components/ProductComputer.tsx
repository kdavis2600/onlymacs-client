import { Typewriter } from "./Typewriter";

const sidebarItems = [
  ["blue", "DeepSeek"],
  ["blue", "Qwen"],
  ["blue", "GPT-OSS"],
  ["green", "Gemma"],
  ["green", "Llama"],
];

const keyClasses = [
  ...Array<string>(12).fill("key"),
  "key wide",
  ...Array<string>(8).fill("key"),
  "key wide",
  "key",
  "key",
  "key space",
  "key",
  "key",
  "key",
];

export function ProductComputer() {
  return (
    <section className="product-col" aria-label="OnlyMacs desktop computer">
      <div className="scene">
        <div className="computer-unit">
          <div className="face front">
            <div className="screen-inset">
              <div className="crt">
                <div className="crt-glow">
                  <div className="crt-ui">
                    <div className="sidebar">
                      <div className="icon-list">
                        {sidebarItems.map(([color, label]) => (
                          <div key={label}>
                            <span
                              className={`icon-circle${color ? ` ${color}` : ""}`}
                            />
                            {label}
                          </div>
                        ))}
                      </div>
                    </div>
                    <div className="main-area">
                      <div className="os-label">OnlyMacs 0.1</div>
                      <div className="window">
                        <div className="window-header">
                          <span>Claude Code</span>
                          <span>[x]</span>
                        </div>
                        <div className="typing-container">
                          <Typewriter />
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div className="logo-badge" />
            <div className="floppy-slot" />

            <div className="sticker sticker-ball" />
            <div className="sticker sticker-star" />
            <div className="sticker sticker-text">
              LOCAL
              <br />
              INTELLIGENCE
            </div>

            <div className="grill">
              {Array.from({ length: 8 }, (_, index) => (
                <div className="vent" key={index} />
              ))}
            </div>
          </div>
          <div className="face back" />
          <div className="face left" />
          <div className="face right" />
          <div className="face top" />
          <div className="face bottom" />

          <div className="keyboard-assembly">
            <div className="kb-base">
              <div className="keys-grid">
                {keyClasses.map((className, index) => (
                  <div className={className} key={`${className}-${index}`} />
                ))}
              </div>
            </div>
            <div className="kb-front" />
            <div className="kb-back" />
            <div className="kb-left" />
            <div className="kb-right" />
            <div className="kb-shadow" />
          </div>
        </div>
      </div>
    </section>
  );
}
