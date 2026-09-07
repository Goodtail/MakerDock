(function () {
  "use strict";
  if (window.top !== window || location.protocol !== 'https:' || !['makerworld.com', 'www.makerworld.com'].includes(location.hostname)) return;
  const post = body => { try { window.webkit.messageHandlers.plateShelf.postMessage(body); } catch {} };
  const P = globalThis.PlateShelfLinkPolicy;
  let enabled = true;
  const candidates = new Map(); // signed asset URLs live only in this tab's memory
  const xhrContexts = new WeakMap();
  const nativeClick = HTMLAnchorElement.prototype.click;
  function visible(element) { return element.getClientRects().length > 0 && getComputedStyle(element).visibility !== "hidden" && !element.closest('[aria-hidden="true"]'); }
  function capture(profileID) {
    const context = P.pageContext(location.href, profileID);
    if (!context) return null;
    const snapshot = { pageURL: context.pageURL, profileURL: context.profileURL, capturedAt: new Date().toISOString(),
      title: document.title.replace(/\s*[-|]\s*(?:무료 3D 프린트 모델\s*[-|]\s*)?MakerWorld\s*$/i, "").slice(0, 500) };
    // This .active card + /instance/ image pattern was observed on MakerWorld's live model page.
    // Never choose the first profile or scrape estimates from reviews/recommended models.
    if (context.profileID && context.profileID === context.visibleProfileID) {
      const cards = Array.from(document.querySelectorAll('.active')).filter(el => visible(el) && el.querySelector('img[src*="/instance/"][alt]') && /플레이트|plates?|盘|プレート/i.test(el.innerText));
      if (cards.length === 1) {
        const img = cards[0].querySelector('img[src*="/instance/"][alt]');
        Object.assign(snapshot, P.profileSummary(cards[0].innerText, img.alt));
      }
    }
    return snapshot;
  }
  function remember(data, source) {
    if (!source || !data || typeof data !== "object") return;
    const body = data.data && typeof data.data === "object" ? data.data : data;
    const parsed = P.parseDownload(body.url, body.name);
    if (!parsed) return;
    const now = Date.now();
    for (const [key, value] of candidates) if (now - value.at > 120000) candidates.delete(key);
    if (candidates.size >= 8) candidates.delete(candidates.keys().next().value);
    candidates.set(parsed.url, { source, at: now });
  }
  function inspected(anchor) {
    if (!anchor || anchor.hasAttribute('data-plateshelf-bypass')) return null;
    const parsed = P.parseDownload(anchor.href, anchor.download);
    if (!parsed) return null;
    const remembered = candidates.get(parsed.url);
    const source = remembered && Date.now() - remembered.at <= 120000 ? remembered.source : capture();
    if (!source) return null;
    const nativeURL = P.handoff(parsed, source);
    if (!nativeURL) return null;
    const record = { nativeURL, originalURL: anchor.href, name: parsed.name, source, routed: enabled };
    document.dispatchEvent(new CustomEvent('plateshelf:captured', { detail: JSON.stringify(record) }));
    return enabled ? nativeURL : null;
  }
  HTMLAnchorElement.prototype.click = function (...args) {
    const replacement = inspected(this);
    if (!replacement) return Reflect.apply(nativeClick, this, args);
    post({kind: 'handoff', url: replacement});
    return undefined;
  };
  // User-clicked real links are supported too; MakerWorld currently uses programmatic anchor.click().
  document.addEventListener('click', event => {
    const anchor = event.composedPath().find(el => el instanceof HTMLAnchorElement);
    if (!anchor || anchor.href.startsWith('plateshelf:')) return;
    const replacement = inspected(anchor);
    if (!replacement) return;
    event.preventDefault();
    post({kind: 'handoff', url: replacement});
  }, true);
  // Observe only the actual profile download API. Do not read cookies, authorization headers,
  // unrelated responses, hidden application stores, or create additional requests.
  const nativeOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...args) {
    const profileID = String(method).toUpperCase() === 'GET' ? P.f3mfProfile(String(url), location.href) : null;
    const source = profileID ? capture(profileID) : null;
    if (source) xhrContexts.set(this, source); else xhrContexts.delete(this);
    return Reflect.apply(nativeOpen, this, [method, url, ...args]);
  };
  const nativeSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function (...args) {
    const source = xhrContexts.get(this);
    if (source) this.addEventListener('load', () => {
      try {
        if (this.status < 200 || this.status >= 300) return;
        if (this.responseType === 'json') remember(this.response, source);
        else if ((!this.responseType || this.responseType === 'text') && this.responseText.length <= 65536) remember(JSON.parse(this.responseText), source);
      } catch { /* Preserve all original site behavior on an unrecognized response. */ }
    }, { once: true });
    return Reflect.apply(nativeSend, this, args);
  };
  const nativeFetch = window.fetch;
  window.fetch = function (input, options) {
    const url = typeof input === 'string' || input instanceof URL ? String(input) : input?.url;
    const method = String(options?.method || input?.method || 'GET').toUpperCase();
    const profileID = method === 'GET' ? P.f3mfProfile(url, location.href) : null;
    const source = profileID ? capture(profileID) : null;
    const promise = Reflect.apply(nativeFetch, this, [input, options]);
    if (source) promise.then(async response => {
      if (!response.ok || !response.body) return;
      const reader = response.clone().body.getReader();
      const chunks = []; let size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read(); if (done) break;
          size += value.byteLength; if (size > 65536) { await reader.cancel(); return; }
          chunks.push(value);
        }
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
        remember(JSON.parse(new TextDecoder().decode(bytes)), source);
      } catch { /* Observing never rejects the site's own promise. */ }
    }).catch(() => {});
    return promise;
  };
  let lastContext = '', contextTimer;
  function reportContext() {
    const source = capture();
    const fingerprint = JSON.stringify(source ? {...source, capturedAt: null} : null);
    if (fingerprint === lastContext) return;
    lastContext = fingerprint;
    post({kind: 'context', json: source ? JSON.stringify(source) : null});
  }
  function scheduleContext() { clearTimeout(contextTimer); contextTimer = setTimeout(reportContext, 180); }
  new MutationObserver(scheduleContext).observe(document, {childList:true, subtree:true, attributes:true, attributeFilter:['class']});
  window.addEventListener('popstate', scheduleContext);
  window.addEventListener('hashchange', scheduleContext);
  document.addEventListener('DOMContentLoaded', scheduleContext);
  for (const name of ['pushState', 'replaceState']) {
    const original = history[name];
    history[name] = function (...args) { const result = Reflect.apply(original, this, args); scheduleContext(); return result; };
  }
  scheduleContext();
})();
