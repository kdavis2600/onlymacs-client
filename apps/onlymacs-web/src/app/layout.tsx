import type { Metadata } from "next";
import { EB_Garamond, VT323 } from "next/font/google";
import "nextra-theme-docs/style.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "OnlyMacs",
  description:
    "OnlyMacs routes AI work across This Mac, trusted private swarms, and public-safe remote capacity.",
};

const ebGaramond = EB_Garamond({
  subsets: ["latin"],
  weight: ["400", "600"],
  style: ["normal", "italic"],
  variable: "--font-eb-garamond",
});

const vt323 = VT323({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-vt323",
});

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${ebGaramond.variable} ${vt323.variable}`}>
        {children}
      </body>
    </html>
  );
}
