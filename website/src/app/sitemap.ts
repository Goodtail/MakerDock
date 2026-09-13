import type { MetadataRoute } from 'next';
import { locales, localePath, siteUrl } from '@/lib/content';
import { languageAlternates } from '@/lib/metadata';
export default function sitemap(): MetadataRoute.Sitemap {
  // Change only when the page content changes, not on each request or build.
  return ['', 'guide'].flatMap(page => locales.map(locale => ({
    url: siteUrl + localePath(locale, page), lastModified: '2026-09-14',
    alternates: { languages: languageAlternates(page) },
  })));
}
