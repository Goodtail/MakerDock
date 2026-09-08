// Follow the signed-in account's existing sidebar link. Creator pages also have
// collection links, so require the paired browsing-history link in the same list.
const findCollections = () => {
  for (const anchor of document.querySelectorAll('a[href]')) {
    let history;
    try { history = new URL(anchor.getAttribute('href'), location.href); }
    catch { continue; }
    if (history.origin !== location.origin ||
        !/^\/(en|ko|ja|zh)\/@[^/]+\/browsing-history\/?$/.test(history.pathname)) continue;
    const list = anchor.closest('ul, nav, [role="list"], [role="navigation"]');
    if (!list) continue;
    const expected = history.pathname.replace(/\/browsing-history\/?$/, '/collections');
    for (const sibling of list.querySelectorAll('a[href]')) {
      let collection;
      try { collection = new URL(sibling.getAttribute('href'), location.href); }
      catch { continue; }
      if (collection.origin === location.origin && collection.pathname.replace(/\/$/, '') === expected) {
        return collection.origin + expected;
      }
    }
  }
  return null;
};
const existing = findCollections();
if (existing) return existing;
// The sidebar is hydrated after navigation. This bounded observer exists only
// for a requested jump and disconnects when found, timed out, or leaving the page.
return await new Promise(resolve => {
  let timer;
  const finish = value => {
    observer.disconnect();
    clearTimeout(timer);
    window.removeEventListener('pagehide', leave);
    resolve(value);
  };
  const leave = () => finish(null);
  const observer = new MutationObserver(() => {
    const found = findCollections();
    if (found) finish(found);
  });
  observer.observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['href']});
  window.addEventListener('pagehide', leave, {once: true});
  timer = setTimeout(() => finish(null), timeoutMilliseconds);
});
