"use client";
import { useRef, useState } from "react";
import { ArrowUpRightIcon, CheckSquareIcon, NotePencilIcon, StackIcon } from "@phosphor-icons/react";
import { Screenshot } from "./screenshot";
import { assetLocale, type Copy, type Locale } from "@/lib/content";
const icons = [StackIcon, NotePencilIcon, CheckSquareIcon];
export function ProductTour({ copy, locale }: { copy: Copy["tour"]; locale: Locale }) {
  const [active, setActive] = useState(0);
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);
  const tab = copy.tabs[active];
  return <div className="tour-grid">
    <div className="tour-controls">
      <div className="tour-tabs" role="tablist" aria-label={copy.label}>
        {copy.tabs.map((item, index) => {
          const Icon = icons[index];
          return <button key={item.id} ref={(node) => { buttons.current[index] = node; }} type="button" role="tab" id={"tab-" + item.id} aria-controls={"panel-" + item.id} aria-selected={active === index} tabIndex={active === index ? 0 : -1} onClick={() => setActive(index)} onKeyDown={(event) => {
            const directions: Record<string, number> = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
            let next = index;
            if (event.key in directions) next = (index + directions[event.key] + copy.tabs.length) % copy.tabs.length;
            else if (event.key === "Home") next = 0;
            else if (event.key === "End") next = copy.tabs.length - 1;
            else return;
            event.preventDefault(); setActive(next); buttons.current[next]?.focus();
          }}><Icon size={22} /><span>{item.label}</span><ArrowUpRightIcon className="tab-arrow" size={18} /></button>;
        })}
      </div>
      <p className="tour-detail">{tab.detail}</p>
    </div>
    {copy.tabs.map((item, index) => <div key={item.id} id={"panel-" + item.id} role="tabpanel" aria-labelledby={"tab-" + item.id} className="tour-panel" tabIndex={0} hidden={index !== active}>
      {index === active && <>
      <Screenshot src={"/screenshots/" + assetLocale(locale) + "/" + tab.id + ".webp"} alt={tab.alt} label={copy.enlarge} close={copy.close} />
      <div className="tour-caption" key={tab.id}><h3>{tab.title}</h3><p>{tab.body}</p></div>
      </>}
    </div>)}
  </div>;
}
