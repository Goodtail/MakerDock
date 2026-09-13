import Image from 'next/image';
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { ArrowDownIcon, ArrowRightIcon, ArrowUpRightIcon, CheckIcon, GithubLogoIcon, HardDrivesIcon, PlusIcon, TabsIcon } from '@phosphor-icons/react/dist/ssr';
import { ProductTour } from '@/components/product-tour';
import { Screenshot } from '@/components/screenshot';
import { SiteHeader, SiteFooter } from '@/components/site-shell';
import { assetLocale, content, downloadUrl, isLocale, localePath, locales, siteUrl, sourceUrl, releaseVersion } from '@/lib/content';
import { guides } from '@/lib/guide';
import { pageMetadata } from '@/lib/metadata';
export const dynamicParams = false;
export function generateStaticParams() { return locales.map(lang => ({ lang })); }
export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  return pageMetadata(lang);
}
export default async function Page({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const c = content[lang], g = guides[lang];
  const pageUrl = siteUrl + localePath(lang);
  const schema = { '@context': 'https://schema.org', '@graph': [
    { '@type': 'Organization', '@id': siteUrl + '/#organization', name: 'Goodtail', url: 'https://goodtail.app', logo: siteUrl + '/icon.png' },
    { '@type': 'WebSite', '@id': siteUrl + '/#website', name: 'MakerDock', url: siteUrl, inLanguage: locales, publisher: { '@id': siteUrl + '/#organization' } },
    { '@type': 'SoftwareApplication', '@id': pageUrl + '#app', name: 'MakerDock', applicationCategory: 'UtilitiesApplication', operatingSystem: 'macOS 13 or later', softwareVersion: releaseVersion, description: c.description, url: pageUrl, inLanguage: lang, downloadUrl, releaseNotes: sourceUrl + '/releases/tag/v' + releaseVersion, screenshot: siteUrl + '/screenshots/' + assetLocale(lang) + '/library.webp', license: sourceUrl + '/blob/main/LICENSE', isAccessibleForFree: true, offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD', url: downloadUrl }, author: { '@id': siteUrl + '/#organization' } },
  ] };
  const download = <><span>{c.nav.download}</span><ArrowDownIcon size={19} weight="bold" /></>;
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(schema).replace(/</g, '\\u003c') }} />
    <SiteHeader locale={lang} />
    <main id="main">
      <section className="hero container" aria-labelledby="hero-title">
        <div className="hero-copy"><div className="hero-heading"><p className="eyebrow">{g.eyebrow}</p><h1 id="hero-title"><span>{c.hero.line1}</span><span>{c.hero.line2}</span></h1></div>
          <div className="hero-action"><p>{c.hero.body}</p><a className="button" href={downloadUrl}>{download}</a><span className="hero-free">{g.free}</span></div>
        </div>
        <div className="hero-window"><Screenshot src={'/screenshots/' + assetLocale(lang) + '/library.webp'} alt={c.hero.alt} label={c.hero.enlarge} close={c.tour.close} hero /></div>
        <div className="hero-caption"><p>{c.ending.compatibility}</p><a className="text-link" href={sourceUrl + '/releases/tag/v' + releaseVersion}>v{releaseVersion}<span>{c.ending.release}</span><ArrowUpRightIcon size={16} /></a></div>
      </section>
      <section className="intro container" aria-labelledby="intro-title">
        <div><span className="section-index" aria-hidden="true">01 / 3MF</span><h2 id="intro-title" className="preserve-lines">{c.intro.title}</h2></div>
        <div className="intro-points">{c.intro.items.map((item, i) => <div key={item.title}><span className="point-index" aria-hidden="true">0{i+1}</span><div><h3>{item.title}</h3><p>{item.body}</p></div></div>)}</div>
      </section>
      <section className="tour-section" id="tour" aria-labelledby="tour-title">
        <div className="container">
          <div className="section-heading"><div><span className="section-index" aria-hidden="true">02 / MakerDock</span><h2 id="tour-title" className="preserve-lines">{c.tour.title}</h2></div><p>{c.tour.body}</p></div>
          <ProductTour copy={c.tour} locale={lang} />
          <p className="demo-caption">{c.tour.demo}</p>
        </div>
      </section>
      <section className="browser-story container" aria-labelledby="browser-title">
        <div className="browser-lead"><div className="local-label"><TabsIcon size={24} /><span>{g.browser.label}</span></div><h2 id="browser-title" className="preserve-lines">{g.browser.title}</h2><p>{g.browser.body}</p><a className="text-link" href={localePath(lang, 'guide') + '#makerworld'}>{g.label}<ArrowRightIcon size={18} /></a></div>
        <div className="browser-details"><ul>{g.browser.items.map(item => <li key={item}><CheckIcon size={20} /><span>{item}</span></li>)}</ul><div className="shortcut"><span><kbd>⌘</kbd><span> + </span><kbd>↖</kbd></span><p>{g.browser.shortcut}</p></div></div>
      </section>
      <section className="ownership container" aria-labelledby="local-title">
        <div className="ownership-lead"><div className="local-label"><HardDrivesIcon size={23} /><span>{c.local.label}</span></div><h2 id="local-title">{c.local.title}</h2><p>{c.local.body}</p><a className="text-link" href={sourceUrl}><GithubLogoIcon size={18} />{c.nav.source}<ArrowUpRightIcon size={18} /></a></div>
        <div className="ownership-points">{c.local.items.map(item => <div key={item.title}><h3>{item.title}</h3><p>{item.body}</p></div>)}</div>
      </section>
      <section className="faq container" id="questions" aria-labelledby="faq-title">
        <div><h2 id="faq-title">{c.faq.title}</h2><a className="text-link faq-guide" href={localePath(lang, 'guide')}>{g.label}<ArrowRightIcon size={18} /></a></div>
        <div className="questions">{c.faq.items.map(item => <details key={item.question}><summary>{item.question}<PlusIcon size={22} /></summary><p>{item.answer}</p></details>)}</div>
      </section>
      <section className="download-section container" aria-labelledby="download-title">
        <div className="download-copy"><Image src="/icon.png" alt="" width={72} height={72} /><div><h2 id="download-title">{c.ending.title}</h2><p>{c.ending.body}</p></div></div>
        <div className="download-action"><a className="button" href={downloadUrl}>{download}</a><small>v{releaseVersion} · {g.free}</small><small>{c.ending.compatibility}</small></div>
      </section>
    </main>
    <SiteFooter locale={lang} />
  </>;
}
