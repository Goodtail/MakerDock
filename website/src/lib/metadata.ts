import type { Metadata } from 'next';
import { assetLocale, content, localePath, locales, siteUrl, type Locale } from './content';
import { guides } from './guide';

export const languageAlternates = (page = '') => Object.fromEntries([
  ...locales.map(locale => [locale, siteUrl + localePath(locale, page)]),
  ['x-default', siteUrl + localePath('en', page)],
]);
const ogLocales: Record<Locale, string> = { en: 'en_US', ko: 'ko_KR', ja: 'ja_JP', 'zh-CN': 'zh_CN' };
export function pageMetadata(locale: Locale, page: '' | 'guide' = ''): Metadata {
  const copy = page ? guides[locale] : content[locale];
  const title = page ? `${copy.title} | MakerDock` : copy.title;
  const description = copy.description;
  const url = siteUrl + localePath(locale, page);
  const image = { url: `/social/${assetLocale(locale)}.png`, width: 1200, height: 630, alt: content[locale].hero.alt };
  return {
    title, description,
    alternates: { canonical: url, languages: languageAlternates(page) },
    openGraph: { type: 'website', siteName: 'MakerDock', title, description, url, locale: ogLocales[locale], alternateLocale: locales.filter(l => l !== locale).map(l => ogLocales[l]), images: [image] },
    twitter: { card: 'summary_large_image', title, description, images: [image] },
  };
}
