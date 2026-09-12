// User-initiated navigation only. No network interception, private APIs, cookies,
// account data or page-wide profile scraping. Never send signed asset addresses.
(() => {
  const modelPage = raw => {
    try {
      const u = new URL(raw, location.href);
      if (u.protocol !== 'https:' || !['makerworld.com', 'www.makerworld.com'].includes(u.hostname) ||
          u.username || u.password || (u.port && u.port !== '443') ||
          !/^\/(?:[a-z]{2}(?:-[A-Za-z]{2})?\/)?models\/[1-9][0-9]*(?:-[^/]+)?\/?$/.test(u.pathname)) return null;
      u.search = ''; u.hash = ''; u.hostname = 'makerworld.com';
      return u.href;
    } catch { return null; }
  };
  const modelKey = raw => raw && new URL(raw).pathname.match(/\/models\/([0-9]+)/)?.[1];
  document.addEventListener('click', event => {
    if (!event.isTrusted || !['makerworld.com', 'www.makerworld.com'].includes(location.hostname)) return;
    const target = event.target instanceof Element ? event.target : event.target?.parentElement;
    if (!target) return;
    // A model opened in a collection overlay may leave the address bar unchanged.
    // Accept a public model link only when the clicked dialog identifies one model.
    const dialog = target.closest('[role="dialog"], dialog');
    const pages = dialog ? [...dialog.querySelectorAll('a[href]')].map(a => modelPage(a.href)).filter(Boolean) : [];
    const unique = new Set(pages.map(modelKey));
    const pageURL = unique.size > 1 ? null : ((unique.size === 1 ? pages[0] : null) || modelPage(location.href));
    window.webkit?.messageHandlers.makerDockNavigation?.postMessage({ kind: 'gesture', documentURL: location.href, pageURL });
    const anchor = target.closest('a[href]');
    if (!event.metaKey || !anchor || anchor.hasAttribute('download')) return;
    try {
      const url = new URL(anchor.href);
      if (url.protocol !== 'https:' || !['makerworld.com', 'www.makerworld.com'].includes(url.hostname) || url.pathname.toLowerCase().endsWith('.3mf')) return;
      event.preventDefault(); event.stopImmediatePropagation();
      window.webkit?.messageHandlers.makerDockNavigation?.postMessage({ kind: 'tab', url: url.href, foreground: event.shiftKey });
    } catch {}
  }, true);
})();
