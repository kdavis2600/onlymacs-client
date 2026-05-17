import { Footer, Layout, Navbar } from "nextra-theme-docs";
import { getPageMap } from "nextra/page-map";
import type { ReactNode } from "react";

const navbar = (
  <Navbar
    logo={<span className="om-docs-logo">OnlyMacs Docs</span>}
    logoLink="/docs"
  />
);

const footer = (
  <Footer>
    <span>OnlyMacs docs for people building real apps on real Macs.</span>
  </Footer>
);

export default async function DocsLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <div className="om-nextra-docs">
      <Layout
        darkMode={false}
        docsRepositoryBase="https://onlymacs.ai/docs"
        editLink={null}
        feedback={{
          content: null,
        }}
        footer={footer}
        navbar={navbar}
        nextThemes={{
          defaultTheme: "dark",
          forcedTheme: "dark",
        }}
        pageMap={await getPageMap("/docs")}
        sidebar={{
          autoCollapse: false,
          defaultMenuCollapseLevel: 1,
          defaultOpen: true,
        }}
        toc={{
          backToTop: "Back to top",
          title: "On this page",
        }}
      >
        {children}
      </Layout>
    </div>
  );
}
