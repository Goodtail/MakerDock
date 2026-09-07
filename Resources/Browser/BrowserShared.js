/* Shared pure policy. Native MakerDock independently validates every field again. */
(function (root) {
  "use strict";
  const exactHosts = new Set(["makerworld.com", "www.makerworld.com", "makerworld.com.cn", "www.makerworld.com.cn", "public-cdn.bblmw.com", "public-cdn.bblmw.cn", "makerworld.bblmw.com", "makerworld.bblmw.cn"]);
  const aws = /^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\.s3(?:(?:[.-](?:[a-z]{2}(?:-[a-z]+){1,2}-[0-9]))|(?:\.dualstack\.[a-z]{2}(?:-[a-z]+){1,2}-[0-9])|(?:-accelerate(?:\.dualstack)?))?\.amazonaws\.com(?:\.cn)?$/;
  const oss = /^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\.oss-[a-z0-9]+(?:-[a-z0-9]+)*\.aliyuncs\.com$/;
  function remoteURL(raw) {
    if (typeof raw !== "string" || raw.length > 20000 || /%(?![0-9a-f]{2})/i.test(raw)) return null;
    try {
      const u = new URL(raw);
      if (u.protocol !== "https:" || u.username || u.password || u.hash || (u.port && u.port !== "443") || u.hostname.endsWith(".")) return null;
      if (!exactHosts.has(u.hostname) && !(aws.test(u.hostname) && !u.hostname.includes("..")) && !(oss.test(u.hostname) && !u.hostname.includes("-internal."))) return null;
      return u.href;
    } catch { return null; }
  }
  function safeName(raw) {
    if (typeof raw !== "string") return null;
    const name = raw.trim();
    return name.length && new TextEncoder().encode(name).length <= 240 && !/[\x00-\x1f\x7f/\\:]/.test(name) && /^.+\.3mf$/i.test(name) ? name : null;
  }
  function parseDownload(raw, suggestedName) {
    if (typeof raw !== "string" || raw.length > 30000) return null;
    try {
      let url, name = suggestedName;
      if (/^bambustudioopen:\/\//i.test(raw)) {
        const payload = raw.slice(raw.indexOf("://") + 3);
        const outerName = payload.indexOf("&name=");
        let decoded;
        if (outerName >= 0) { decoded = decodeURIComponent(payload.slice(0, outerName)); name = decodeURIComponent(payload.slice(outerName + 6)); }
        else {
          decoded = decodeURIComponent(payload);
          const trailer = decoded.indexOf("&name=");
          if (trailer >= 0) { name = decoded.slice(trailer + 6); decoded = decoded.slice(0, trailer); }
        }
        url = remoteURL(decoded);
      } else if (/^bambustudio:\/\//i.test(raw)) {
        const u = new URL(raw);
        if (u.hostname !== "open" || u.searchParams.getAll("file").length !== 1) return null;
        let decoded = u.searchParams.get("file");
        const trailer = decoded.indexOf("&name=");
        if (trailer >= 0) { name = decoded.slice(trailer + 6); decoded = decoded.slice(0, trailer); }
        name = u.searchParams.get("name") || name;
        url = remoteURL(decoded);
      } else {
        url = remoteURL(raw);
        if (!url) return null;
        const path = new URL(url).pathname;
        if (!name && /\.3mf$/i.test(path)) name = decodeURIComponent(path.split("/").pop());
        // Plain web links must genuinely identify a 3MF, never an API/search/image URL.
        if (!safeName(name)) return null;
      }
      if (!url) return null;
      name = name || decodeURIComponent(new URL(url).pathname.split("/").pop());
      if (!safeName(name)) return null;
      return { url, name, action: /^bambustudio(?:open)?:/i.test(raw) ? 'open' : 'import' };
    } catch { return null; }
  }
  function pageContext(raw, explicitProfileID) {
    try {
      const u = new URL(raw);
      if (u.protocol !== "https:" || !["makerworld.com", "www.makerworld.com"].includes(u.hostname) || u.username || u.password || u.port) return null;
      if (!/^\/(?:[a-z]{2}(?:-[A-Za-z]{2})?\/)?models\/[1-9][0-9]*(?:-[^/]+)?\/?$/.test(u.pathname)) return null;
      const fromHash = /^#profileId-([1-9][0-9]*)$/.exec(u.hash)?.[1];
      const fromQuery = u.searchParams.get("printProfileId") || u.searchParams.get("profileId");
      const profileID = explicitProfileID || fromHash || fromQuery;
      if (profileID && !/^[1-9][0-9]*$/.test(profileID)) return null;
      u.hostname = "makerworld.com"; u.search = ""; u.hash = "";
      return { pageURL: u.href, profileURL: profileID ? u.href + "#profileId-" + profileID : null, profileID: profileID || null, visibleProfileID: fromHash || fromQuery || null };
    } catch { return null; }
  }
  function duration(text) {
    if (typeof text !== "string") return null;
    const normalized = text.trim().replace(/,/g, ".").toLowerCase();
    const re = /(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|시간|小时|時|minutes?|mins?|min|m|분|分钟|分|seconds?|secs?|sec|s|초|秒)/g;
    let seconds = 0, found = false, match;
    while ((match = re.exec(normalized))) {
      const unit = match[2];
      const factor = /^(h|시간|小时|時)/.test(unit) ? 3600 : /^(m|분|分钟|分)/.test(unit) ? 60 : 1;
      seconds += Number(match[1]) * factor; found = true;
    }
    return found && normalized.replace(re, "").trim() === "" && seconds > 0 && seconds <= 31536000 ? Math.round(seconds) : null;
  }
  function profileSummary(text, profileTitle) {
    const lines = String(text || "").split(/\n/).map(s => s.trim()).filter(Boolean);
    const times = lines.map(duration).filter(v => v !== null);
    const count = /(?:^|\n)(\d{1,3})\s*(?:\n\s*)?(?:플레이트|plates?|盘|プレート)(?:$|\n)/i.exec(lines.join("\n"));
    return { profileTitle: typeof profileTitle === "string" ? profileTitle.slice(0, 500) : null,
      estimatedSeconds: times.length === 1 ? times[0] : null,
      plateCount: count && Number(count[1]) > 0 && Number(count[1]) <= 256 ? Number(count[1]) : null };
  }
  function f3mfProfile(raw, base) {
    try {
      const u = new URL(raw, base);
      if (u.origin !== new URL(base).origin) return null;
      return /^\/(?:api\/)?v1\/design-service\/instance\/([1-9][0-9]*)\/f3mf$/.exec(u.pathname)?.[1] || null;
    } catch { return null; }
  }
  function handoff(download, source) {
    const checked = parseDownload(download.url, download.name);
    const context = pageContext(source?.pageURL);
    if (!checked || !context) return null;
    const u = new URL("makerdock://open");
    u.searchParams.set("action", download.action === 'open' ? 'open' : 'import');
    u.searchParams.set("url", checked.url); u.searchParams.set("name", checked.name); u.searchParams.set("source", context.pageURL);
    if (source.profileURL) {
      const profile = pageContext(source.profileURL);
      if (!profile?.profileURL || profile.pageURL !== context.pageURL) return null;
      u.searchParams.set("profile", profile.profileURL);
    }
    const snapshot = { capturedAt: source.capturedAt, title: source.title };
    if (source.profileURL) for (const key of ["profileTitle", "estimatedSeconds", "plateCount", "plates"]) if (source[key] != null) snapshot[key] = source[key];
    const json = JSON.stringify(snapshot);
    if (new TextEncoder().encode(json).length > 24000) return null;
    u.searchParams.set("snapshot", json);
    return u.href.length <= 65000 ? u.href : null;
  }
  const api = Object.freeze({ remoteURL, safeName, parseDownload, pageContext, duration, profileSummary, f3mfProfile, handoff });
  root.PlateShelfLinkPolicy = api;
  if (typeof module !== "undefined") module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
