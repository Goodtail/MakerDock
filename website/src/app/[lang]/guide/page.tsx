import { notFound } from 'next/navigation';
import { ArrowLeftIcon, ArrowDownIcon } from '@phosphor-icons/react/dist/ssr';
import { SiteHeader, SiteFooter } from '@/components/site-shell';
import { Screenshot } from '@/components/screenshot';
import { assetLocale, content, downloadUrl, isLocale, localePath, siteUrl } from '@/lib/content';
import { guides } from '@/lib/guide';
import { pageMetadata } from '@/lib/metadata';
export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  return pageMetadata(lang, 'guide');
}
export default async function GuidePage({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const g = guides[lang], c = content[lang];
  const schema = { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [
    { '@type': 'ListItem', position: 1, name: 'MakerDock', item: siteUrl + localePath(lang) },
    { '@type': 'ListItem', position: 2, name: g.label, item: siteUrl + localePath(lang, 'guide') },
  ] };
  return <><SiteHeader locale={lang} page="guide" /><main id="main" className="guide-page container">
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(schema).replace(/</g, '\\u003c') }} />
    <a className="text-link" href={localePath(lang)}><ArrowLeftIcon size={16} />{g.back}</a>
    <div className="guide-heading"><p className="eyebrow">{g.label}</p><h1>{g.title}</h1><p>{g.description}</p></div>
    <div className="guide-layout"><nav className="guide-toc" aria-label={g.label}>{g.sections.map(section => <a key={section.id} href={'#' + section.id}>{section.title}</a>)}</nav>
      <article className="guide-content">{g.sections.map(section => <section key={section.id} id={section.id}><h2>{section.title}</h2>{section.body.map(p => <p key={p}>{p}</p>)}{section.id === 'queue' && <Screenshot src={'/screenshots/' + assetLocale(lang) + '/queue.webp'} alt={c.tour.tabs.find(t => t.id === 'queue')!.alt} label={c.tour.enlarge} close={c.tour.close} />}</section>)}
      <a className="button" href={downloadUrl}>{c.nav.download}<ArrowDownIcon size={18} /></a></article>
    </div>
  </main><SiteFooter locale={lang} /></>;
}
