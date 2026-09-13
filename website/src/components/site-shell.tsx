import Image from 'next/image';
import { ArrowDownIcon, ArrowUpRightIcon, CaretDownIcon, GlobeIcon } from '@phosphor-icons/react/dist/ssr';
import { Appearance } from './preferences';
import { content, downloadUrl, localeNames, localePath, locales, sourceUrl, type Locale } from '@/lib/content';
import { guides } from '@/lib/guide';

export function SiteHeader({ locale, page = '' }: { locale: Locale; page?: string }) {
  const c = content[locale];
  const home = localePath(locale);
  return <><a className="skip-link" href="#main">{c.skip}</a><header className="site-header">
    <nav className="nav-shell container" aria-label="MakerDock">
      <a className="brand" href={home} aria-label="MakerDock"><Image src="/icon.png" alt="" width={42} height={42} /><span>MakerDock</span></a>
      <div className="nav-links"><a href={home + '#tour'}>{c.nav.tour}</a><a href={localePath(locale, 'guide')} aria-current={page === 'guide' ? 'page' : undefined}>{guides[locale].label}</a></div>
      <div className="nav-actions">
        <details className="language dropdown"><summary aria-label={c.nav.language + ': ' + localeNames[locale]} title={c.nav.language}><GlobeIcon size={20} /><span className="language-label">{localeNames[locale]}</span><CaretDownIcon size={11} /></summary>
          <div className="dropdown-panel">{locales.map(l => <a key={l} href={localePath(l, page)} hrefLang={l} lang={l} aria-current={l === locale ? 'page' : undefined}>{localeNames[l]}</a>)}</div>
        </details>
        <Appearance copy={c.nav} />
        <a className="button button-small nav-download" href={downloadUrl}>{c.nav.download}<ArrowDownIcon size={17} /></a>
      </div>
    </nav>
  </header></>;
}
export function SiteFooter({ locale }: { locale: Locale }) {
  const c = content[locale];
  return <footer className="site-footer container">
    <div className="footer-row"><a className="footer-goodtail" href="https://goodtail.app">{c.footer.by}<ArrowUpRightIcon size={15} /></a>
      <div><a href={localePath(locale, 'guide')}>{guides[locale].label}</a><a href={sourceUrl}>GitHub</a><a href={sourceUrl + '/blob/main/PRIVACY.md'}>{c.footer.privacy}</a><a href={sourceUrl + '/blob/main/LICENSE'}>{c.footer.license}</a></div>
    </div><p>{c.footer.disclaimer}</p>
  </footer>;
}
