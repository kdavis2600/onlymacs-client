import { generateStaticParamsFor, importPage } from "nextra/pages";
import type { ComponentType, ReactNode } from "react";

import { useMDXComponents as getMDXComponents } from "@/mdx-components";

type PageProps = {
  params: Promise<{
    mdxPath?: string[];
  }>;
};

const generateBaseStaticParams = generateStaticParamsFor("mdxPath");

type StaticParam = {
  mdxPath?: string[];
};

function mapDocsAliasPath(mdxPath?: string[]) {
  if (mdxPath?.[0] === "app") {
    return ["mac-app", ...mdxPath.slice(1)];
  }

  return mdxPath;
}

export async function generateStaticParams() {
  const params = (await generateBaseStaticParams()) as StaticParam[];
  const appAliases = params
    .filter((param) => param.mdxPath?.[0] === "mac-app")
    .map((param) => ({
      mdxPath: ["app", ...(param.mdxPath ?? []).slice(1)],
    }));

  return [...params, ...appAliases];
}

export async function generateMetadata({ params }: PageProps) {
  const { mdxPath } = await params;
  const { metadata } = await importPage(mapDocsAliasPath(mdxPath));

  return metadata;
}

const Wrapper = getMDXComponents().wrapper as ComponentType<{
  children: ReactNode;
  metadata: Record<string, unknown>;
  toc: unknown;
}>;

export default async function DocsPage(props: PageProps) {
  const params = await props.params;
  const { default: MDXContent, metadata, toc } = await importPage(
    mapDocsAliasPath(params.mdxPath),
  );

  return (
    <Wrapper metadata={metadata} toc={toc}>
      <MDXContent {...props} params={params} />
    </Wrapper>
  );
}
