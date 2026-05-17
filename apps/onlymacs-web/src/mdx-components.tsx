import { useMDXComponents as getThemeComponents } from "nextra-theme-docs";
import type { MDXComponents } from "mdx/types";

import {
  Avoid,
  BestDefault,
  Decision,
  Example,
  Learn,
  NextStep,
  Note,
  Recipe,
  Troubleshooting,
} from "@/components/DocsBlocks";

const themeComponents = getThemeComponents();

export function useMDXComponents(components: MDXComponents = {}): MDXComponents {
  return {
    ...themeComponents,
    Avoid,
    BestDefault,
    Decision,
    Example,
    Learn,
    NextStep,
    Note,
    Recipe,
    Troubleshooting,
    ...components,
  };
}
