import Image from "next/image";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ArrowDownIcon, ArrowUpRightIcon, CaretDownIcon, GithubLogoIcon, GlobeIcon, HardDrivesIcon, PlusIcon } from "@phosphor-icons/react/dist/ssr";
import { Appearance } from "@/components/preferences";
import { ProductTour } from "@/components/product-tour";
import { Screenshot } from "@/components/screenshot";
import { assetLocale, content, downloadUrl, isLocale, localeNames, localePath, locales, siteUrl, sourceUrl, releaseVersion } from "@/lib/content";
export const dynamicParams = false;
export function generateStaticParams() { return locales.map(lang => ({ lang })); }
export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const copy = content[lang];
  const canonical = localePath(lang);
  return {
    title: copy.title, description: copy.description,
    alternates: { canonical, languages: { en: "/", ko: "/ko", ja: "/ja", "zh-CN": "/zh-CN", "x-default": "/" } },
    openGraph: { type: "website", siteName: "MakerDock", title: copy.title, description: copy.description, url: canonical, locale: lang.replace("-", "_"), images: [{ url: "/og.png", width: 1200, height: 782, alt: "MakerDock, a 3D printing library for Mac" }] },
    twitter: { card: "summary_large_image", title: copy.title, description: copy.description, images: ["/og.png"] },
  };
}
export default async function Page({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const c = content[lang];
  const schema = { "@context": "https://schema.org", "@type": "SoftwareApplication", name: "MakerDock", applicationCategory: "UtilitiesApplication", operatingSystem: "macOS 13 or later", softwareVersion: releaseVersion, description: c.description, url: siteUrl, downloadUrl, license: sourceUrl + "/blob/main/LICENSE", offers: { "@type": "Offer", price: "0", priceCurrency: "USD" }, author: { "@type": "Organization", name: "Goodtail", url: "https://goodtail.app" } };
  const download = <><span>{c.nav.download}</span><ArrowDownIcon size={19} weight="bold" /></>;
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(schema).replace(/</g, "\\u003c") }} />
    <a className="skip-link" href="#main">{c.skip}</a>
    <header className="site-header">
      <nav className="nav-shell container" aria-label="MakerDock">
        <a className="brand" href={localePath(lang)} aria-label="MakerDock"><Image src="/icon.png" alt="" width={42} height={42} /><span>MakerDock</span></a>
        <div className="nav-links"><a href="#tour">{c.nav.tour}</a><a href="#questions">{c.nav.faq}</a></div>
        <div className="nav-actions">
          <details className="language dropdown"><summary aria-label={c.nav.language + ": " + localeNames[lang]} title={c.nav.language}><GlobeIcon size={20} /><span className="language-label">{localeNames[lang]}</span><CaretDownIcon size={11} /></summary>
            <div className="dropdown-panel">{locales.map(locale => <a key={locale} href={localePath(locale)} hrefLang={locale} lang={locale} aria-current={locale === lang ? "page" : undefined}>{localeNames[locale]}</a>)}</div>
          </details>
          <Appearance copy={c.nav} />
          <a className="button button-small nav-download" href={downloadUrl}>{download}</a>
        </div>
      </nav>
    </header>
    <main id="main">
      <section className="hero container" aria-labelledby="hero-title">
        <div className="hero-copy"><h1 id="hero-title"><span>{c.hero.line1}</span><span>{c.hero.line2}</span></h1>
          <div className="hero-action"><p>{c.hero.body}</p><a className="button" href={downloadUrl}>{download}</a></div>
        </div>
        <div className="hero-window"><Screenshot src={"/screenshots/" + assetLocale(lang) + "/library.webp"} alt={c.hero.alt} label={c.hero.enlarge} close={c.tour.close} hero /></div>
        <div className="hero-caption"><p>{c.hero.caption}</p><a className="text-link" href={sourceUrl}><GithubLogoIcon size={18} />{c.nav.source}<ArrowUpRightIcon size={16} /></a></div>
      </section>
      <section className="intro container" aria-labelledby="intro-title">
        <h2 id="intro-title" className="preserve-lines">{c.intro.title}</h2>
        <div className="intro-points">{c.intro.items.map((item) => <div key={item.title}><h3>{item.title}</h3><p>{item.body}</p></div>)}</div>
      </section>
      <section className="tour-section" id="tour" aria-labelledby="tour-title">
        <div className="container">
          <div className="section-heading"><h2 id="tour-title" className="preserve-lines">{c.tour.title}</h2><p>{c.tour.body}</p></div>
          <ProductTour copy={c.tour} locale={lang} />
          <p className="demo-caption">{c.tour.demo}</p>
        </div>
      </section>
      <section className="ownership container" aria-labelledby="local-title">
        <div className="ownership-lead"><div className="local-label"><HardDrivesIcon size={23} /><span>{c.local.label}</span></div><h2 id="local-title">{c.local.title}</h2><p>{c.local.body}</p><a className="text-link" href={sourceUrl}>{c.nav.source}<ArrowUpRightIcon size={18} /></a></div>
        <div className="ownership-points">{c.local.items.map(item => <div key={item.title}><h3>{item.title}</h3><p>{item.body}</p></div>)}</div>
      </section>
      <section className="faq container" id="questions" aria-labelledby="faq-title">
        <h2 id="faq-title">{c.faq.title}</h2>
        <div className="questions">{c.faq.items.map((item) => <details key={item.question}><summary>{item.question}<PlusIcon size={22} /></summary><p>{item.answer}</p></details>)}</div>
      </section>
      <section className="download-section container" aria-labelledby="download-title">
        <Image src="/icon.png" alt="" width={88} height={88} />
        <h2 id="download-title">{c.ending.title}</h2><p>{c.ending.body}</p>
        <a className="button" href={downloadUrl}>{download}</a>
        <small>{c.ending.compatibility}</small>
        <a className="release-link" href={sourceUrl + "/releases/tag/v" + releaseVersion}>{c.ending.release}<ArrowUpRightIcon size={14} /></a>
      </section>
    </main>
    <footer className="site-footer container">
      <div className="footer-row"><a className="footer-goodtail" href="https://goodtail.app">{c.footer.by}<ArrowUpRightIcon size={15} /></a>
        <div><a href={sourceUrl}>GitHub</a><a href={sourceUrl + "/blob/main/PRIVACY.md"}>{c.footer.privacy}</a><a href={sourceUrl + "/blob/main/LICENSE"}>{c.footer.license}</a></div>
      </div><p>{c.footer.disclaimer}</p>
    </footer>
  </>;
}
