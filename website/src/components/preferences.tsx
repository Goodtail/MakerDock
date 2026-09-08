"use client";
import { useSyncExternalStore } from "react";
import { DesktopIcon, MoonIcon, SunIcon } from "@phosphor-icons/react";
import type { Copy } from "@/lib/content";

function subscribe(callback: () => void) {
  window.addEventListener("makerdock-theme", callback);
  window.addEventListener("storage", callback);
  return () => { window.removeEventListener("makerdock-theme", callback); window.removeEventListener("storage", callback); };
}
function getSnapshot() { return document.documentElement.dataset.theme || "system"; }
export function Appearance({ copy }: { copy: Copy["nav"] }) {
  const theme = useSyncExternalStore(subscribe, getSnapshot, () => "system");
  function setTheme(value: string) {
    if (value === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", value);
    try { localStorage.setItem("makerdock-theme", value); } catch {}
    window.dispatchEvent(new Event("makerdock-theme"));
  }
  return <details className="appearance dropdown">
    <summary aria-label={copy.theme} title={copy.theme}><span className="theme-light"><SunIcon size={20} /></span><span className="theme-dark"><MoonIcon size={20} /></span></summary>
    <div className="dropdown-panel" role="group" aria-label={copy.theme}>
      {([["light", copy.light, SunIcon], ["dark", copy.dark, MoonIcon], ["system", copy.system, DesktopIcon]] as const).map(([value, label, Icon]) =>
        <button key={value} type="button" aria-pressed={theme === value} onClick={(event) => { setTheme(value); event.currentTarget.closest("details")?.removeAttribute("open"); }}><Icon size={18} />{label}</button>
      )}
    </div>
  </details>;
}
