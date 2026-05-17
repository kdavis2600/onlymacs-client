import type { NextConfig } from "next";
import nextra from "nextra";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const appRoot = dirname(fileURLToPath(import.meta.url));
const withNextra = nextra({
  contentDirBasePath: "/docs",
});

const nextConfig: NextConfig = {
  output: "export",
  turbopack: {
    root: appRoot,
  },
};

export default withNextra(nextConfig);
