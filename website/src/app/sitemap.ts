import type { MetadataRoute } from "next";
import { locales, localePath, siteUrl } from "@/lib/content";
export default function sitemap(): MetadataRoute.Sitemap {
  return locales.map(locale => ({ url: siteUrl + localePath(locale), alternates: { languages: { en: siteUrl, ko: siteUrl + "/ko", ja: siteUrl + "/ja", "zh-CN": siteUrl + "/zh-CN" } } }));
}
