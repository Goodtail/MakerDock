import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import { notFound } from "next/navigation";
import { isLocale, siteUrl } from "@/lib/content";
import "../globals.css";

const manrope = localFont({
  src: "../../fonts/manrope-latin-wght-normal.woff2",
  variable: "--font-display", display: "swap", weight: "200 800",
});
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  icons: { icon: "/icon.png", apple: "/apple-touch-icon.png" },
};
export const viewport: Viewport = {
  width: "device-width", initialScale: 1,
  themeColor: [{ media: "(prefers-color-scheme: light)", color: "#ffffff" }, { media: "(prefers-color-scheme: dark)", color: "#151515" }],
};
const themeInit = "(function(){try{var t=localStorage.getItem('makerdock-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t;}catch(e){}})();";
export default async function RootLayout({ children, params }: { children: React.ReactNode; params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  return <html lang={lang} className={manrope.variable} suppressHydrationWarning>
    <head><script dangerouslySetInnerHTML={{ __html: themeInit }} /></head>
    <body>{children}</body>
  </html>;
}
