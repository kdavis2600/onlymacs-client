import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const appRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(appRoot, "..", "..");
const contentRoot = path.join(appRoot, "src", "content");
const defaultOutputPath = path.join(repoRoot, ".tmp", "onlymacs-docs-corpus.json");

const docsComponents = new Set([
  "Avoid",
  "BestDefault",
  "Decision",
  "Example",
  "Learn",
  "NextStep",
  "Note",
  "Recipe",
  "Troubleshooting",
]);

const args = parseArgs();
const outputPath = path.resolve(appRoot, args.output || defaultOutputPath);
const documents = collectDocs(contentRoot).map((filePath, index) => {
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = parseFrontmatter(raw);
  const headings = extractHeadings(parsed.body);
  const title = parsed.frontmatter.title || headings.find((heading) => heading.depth === 1)?.text || routeForFile(filePath);

  return {
    order: index + 1,
    route: routeForFile(filePath),
    url: `https://onlymacs.ai${routeForFile(filePath)}`,
    source_path: path.relative(repoRoot, filePath).replace(/\\/g, "/"),
    title,
    description: parsed.frontmatter.description || "",
    headings,
    content_mdx: parsed.body.trim(),
    content_text: mdxToPlainText(parsed.body),
  };
});

const generatedAt = new Date().toISOString();
const corpus = {
  schema: "onlymacs.docs_corpus.v1",
  generated_at: generatedAt,
  source: {
    project: "OnlyMacs",
    docs_root: path.relative(repoRoot, contentRoot).replace(/\\/g, "/"),
    public_base_url: "https://onlymacs.ai/docs",
    generator: path.relative(repoRoot, fileURLToPath(import.meta.url)).replace(/\\/g, "/"),
  },
  summary: {
    document_count: documents.length,
    routes: documents.map((doc) => doc.route),
    purpose: "Generated local docs search/review corpus. Not committed.",
  },
  documents,
  combined_markdown: buildCombinedMarkdown(documents, generatedAt),
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(corpus, null, 2)}\n`, "utf8");

console.log(JSON.stringify({
  ok: true,
  output: path.relative(repoRoot, outputPath).replace(/\\/g, "/"),
  document_count: documents.length,
  bytes: fs.statSync(outputPath).size,
}, null, 2));

function parseArgs() {
  const parsed = { output: null };
  for (let index = 2; index < process.argv.length; index += 1) {
    const arg = process.argv[index];
    if (arg === "--output") {
      parsed.output = process.argv[index + 1] || null;
      index += 1;
      continue;
    }
    if (arg.startsWith("--output=")) {
      parsed.output = arg.slice("--output=".length);
    }
  }
  return parsed;
}

function collectDocs(root) {
  const files = [];

  function visit(dir) {
    const metaOrder = readMetaOrder(dir);
    const entries = fs.readdirSync(dir, { withFileTypes: true })
      .filter((entry) => entry.name !== "_meta.ts")
      .filter((entry) => entry.isDirectory() || entry.name.endsWith(".mdx"))
      .sort((left, right) => compareEntries(left, right, metaOrder));

    for (const entry of entries) {
      const entryPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        visit(entryPath);
      } else {
        files.push(entryPath);
      }
    }
  }

  visit(root);
  return files;
}

function compareEntries(left, right, metaOrder) {
  const leftKey = entryKey(left);
  const rightKey = entryKey(right);
  const leftIndex = metaOrder.get(leftKey);
  const rightIndex = metaOrder.get(rightKey);
  if (leftIndex != null && rightIndex != null) return leftIndex - rightIndex;
  if (leftIndex != null) return -1;
  if (rightIndex != null) return 1;
  return leftKey.localeCompare(rightKey);
}

function entryKey(entry) {
  return entry.isDirectory() ? entry.name : entry.name.replace(/\.mdx$/, "");
}

function readMetaOrder(dir) {
  const metaPath = path.join(dir, "_meta.ts");
  const order = new Map();
  if (!fs.existsSync(metaPath)) return order;

  const raw = fs.readFileSync(metaPath, "utf8");
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return order;

  const body = raw.slice(start + 1, end);
  const keyPattern = /(?:^|,|\n)\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z_$][\w$]*))\s*:/g;
  let match = keyPattern.exec(body);
  while (match) {
    const key = match[1] || match[2] || match[3];
    if (key && !order.has(key)) order.set(key, order.size);
    match = keyPattern.exec(body);
  }
  return order;
}

function parseFrontmatter(content) {
  if (!content.startsWith("---\n")) {
    return { frontmatter: {}, body: content };
  }
  const close = content.indexOf("\n---\n", 4);
  if (close === -1) return { frontmatter: {}, body: content };

  const frontmatter = {};
  const frontmatterBody = content.slice(4, close);
  for (const line of frontmatterBody.split("\n")) {
    const separator = line.indexOf(":");
    if (separator === -1) continue;
    const key = line.slice(0, separator).trim();
    const value = line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, "");
    if (key) frontmatter[key] = value;
  }

  return {
    frontmatter,
    body: content.slice(close + "\n---\n".length),
  };
}

function routeForFile(filePath) {
  const relative = path.relative(contentRoot, filePath).replace(/\\/g, "/");
  const withoutExt = relative.replace(/\.mdx$/, "");
  if (withoutExt === "index") return "/docs";
  if (withoutExt.endsWith("/index")) {
    return `/docs/${withoutExt.slice(0, -"/index".length)}`;
  }
  return `/docs/${withoutExt}`;
}

function extractHeadings(body) {
  const headings = [];
  for (const line of body.split(/\r?\n/)) {
    const match = line.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/);
    if (!match) continue;
    headings.push({
      depth: match[1].length,
      text: stripMarkdownInline(match[2]).trim(),
    });
  }
  return headings;
}

function mdxToPlainText(body) {
  return body
    .replace(/<([A-Z][A-Za-z0-9]*)([^>]*)>/g, (_, component, attrs) => {
      if (!docsComponents.has(component)) return "";
      const title = extractTitleAttribute(attrs);
      return `\n[${component}${title ? `: ${title}` : ""}]\n`;
    })
    .replace(/<\/([A-Z][A-Za-z0-9]*)>/g, "\n")
    .split(/\r?\n/)
    .map((line) => stripMarkdownInline(line).trimEnd())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function extractTitleAttribute(attrs) {
  const match = attrs.match(/\btitle=(?:"([^"]*)"|'([^']*)')/);
  return match ? (match[1] || match[2] || "").trim() : "";
}

function stripMarkdownInline(text) {
  return text
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/_([^_]+)_/g, "$1")
    .replace(/<[^>]+>/g, "");
}

function buildCombinedMarkdown(docs, generatedAt) {
  const toc = docs
    .map((doc) => `${doc.order}. [${doc.title}](${doc.url}) - ${doc.route}`)
    .join("\n");

  const pages = docs.map((doc) => [
    "---",
    `Route: ${doc.route}`,
    `URL: ${doc.url}`,
    `Source: ${doc.source_path}`,
    `Title: ${doc.title}`,
    doc.description ? `Description: ${doc.description}` : null,
    "---",
    "",
    doc.content_mdx,
  ].filter(Boolean).join("\n")).join("\n\n");

  return [
    "# OnlyMacs Docs Corpus",
    "",
    `Generated: ${generatedAt}`,
    "",
    "This section is a single markdown view of every public OnlyMacs docs page.",
    "",
    "## Table Of Contents",
    "",
    toc,
    "",
    pages,
  ].join("\n");
}
