"use client";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { ArrowsOutIcon, XIcon } from "@phosphor-icons/react";

type Props = { src: string; alt: string; label: string; close: string; hero?: boolean };
export function Screenshot({ src, alt, label, close, hero = false }: Props) {
  const [open, setOpen] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (!open) return;
    const node = dialog.current;
    const previous = document.body.style.overflow;
    node?.showModal();
    document.body.style.overflow = "hidden";
    return () => { node?.close(); document.body.style.overflow = previous; };
  }, [open]);
  return <>
    <button type="button" className={"screenshot-button" + (hero ? " hero-screenshot" : "")} aria-label={label} aria-haspopup="dialog" onClick={() => setOpen(true)}>
      <Image src={src} alt={alt} width={2640} height={1720} sizes={hero ? "(max-width: 768px) 96vw, (max-width: 1400px) 94vw, 1280px" : "(max-width: 768px) 92vw, (max-width: 1200px) 65vw, 920px"} preload={hero} />
      <span className="expand-corner" aria-hidden="true"><ArrowsOutIcon size={19} /></span>
    </button>
    <dialog ref={dialog} className="lightbox" aria-label={label} onCancel={() => setOpen(false)} onClick={(event) => { if (event.target === event.currentTarget) setOpen(false); }}>
      <div className="lightbox-toolbar"><p>{label}</p><button type="button" className="icon-button" aria-label={close} onClick={() => setOpen(false)} autoFocus><XIcon size={24} /></button></div>
      <div className="lightbox-viewport">{open && <Image src={src} alt={alt} width={2640} height={1720} sizes="(max-width: 780px) 740px, 95vw" className="lightbox-image" />}</div>
    </dialog>
  </>;
}
