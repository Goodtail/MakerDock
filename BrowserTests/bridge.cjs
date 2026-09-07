const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const P = require('../Resources/Browser/BrowserShared.js');
const script = fs.readFileSync(path.join(__dirname, '../Resources/Browser/BrowserBridge.js'), 'utf8');
const page = 'https://makerworld.com/ko/models/123-rack';
const profile = page + '#profileId-456';
const asset = 'https://public-cdn.bblmw.com/fixture.3mf?Signature=TEST';
function harness(href=profile, child=false) {
  const posts=[], navigations=[], listeners=new Map(), timers=new Map(); let serial=0;
  class Anchor {
    constructor() { this.attrs={}; }
    get href(){return this.attrs.href || '';} set href(v){this.attrs.href=v;}
    get download(){return this.attrs.download || '';} set download(v){this.attrs.download=v;}
    hasAttribute(k){return k in this.attrs;} getAttribute(k){return this.attrs[k] ?? null;}
    setAttribute(k,v){this.attrs[k]=v;} removeAttribute(k){delete this.attrs[k];}
    click(){navigations.push(this.href);}
  }
  class XHR {
    constructor(){this.listeners={};}
    open(){} send(){} addEventListener(t,f){this.listeners[t]=f;}
    finish(body){this.status=200;this.responseType='json';this.response=body;this.listeners.load?.();}
  }
  const card={getClientRects:()=>[{}],closest:()=>null,querySelector:()=>({alt:'Mega + Pack'}),innerText:'Mega + Pack\n11.7 h\n7\n플레이트'};
  const document={title:'필라멘트 랙 - MakerWorld',querySelectorAll:()=>[card],
    addEventListener(t,f){listeners.set(t,[...(listeners.get(t)||[]),f]);},
    dispatchEvent(e){for(const f of listeners.get(e.type)||[])f(e);},createElement:()=>new Anchor()};
  const location=new URL(href);
  const c={PlateShelfLinkPolicy:P,document,location,HTMLAnchorElement:Anchor,XMLHttpRequest:XHR,
    CustomEvent:class{constructor(type,{detail}){this.type=type;this.detail=detail;}},
    MutationObserver:class{observe(){}},getComputedStyle:()=>({visibility:'visible'}),
    setTimeout:f=>{timers.set(++serial,f);return serial;},clearTimeout:id=>timers.delete(id),
    URL,Date,Map,WeakMap,Set,JSON,TextEncoder,TextDecoder,Uint8Array,Reflect};
  c.window=c;c.top=child?{}:c;c.addEventListener=document.addEventListener.bind(document);
  c.history={pushState(){},replaceState(){}};
  c.webkit={messageHandlers:{plateShelf:{postMessage:body=>posts.push(body)}}};
  c.fetch=()=>Promise.reject(new Error('Network is forbidden in this test'));
  vm.runInNewContext(script,c);
  return {c,posts,navigations,Anchor,XHR,card,flush(){for(const f of timers.values())f();timers.clear();}};
}
const h=harness(); h.flush();
assert.equal(h.posts[0].kind,'context');assert.equal(JSON.parse(h.posts[0].json).plateCount,7);
const request=new h.XHR();request.open('GET','/api/v1/design-service/instance/456/f3mf');request.send();
h.c.location.href=page+'#profileId-789';h.card.innerText='Other Pack\n2 h\n2\n플레이트';
request.finish({url:asset,name:'Mega + Pack.3mf'});
const a=new h.Anchor();a.href=asset;a.download='Mega + Pack.3mf';a.click();
const u=new URL(h.posts.at(-1).url);
assert.equal(h.posts.at(-1).kind,'handoff');assert.equal(u.searchParams.get('profile'),profile);
assert.equal(JSON.parse(u.searchParams.get('snapshot')).estimatedSeconds,42120);
assert.equal(u.searchParams.get('name'),'Mega + Pack.3mf');assert.equal(u.searchParams.get('action'),'import');
assert.equal(h.navigations.length,0);assert.equal(a.href,asset);assert.equal(a.download,'Mega + Pack.3mf');
const studio=new h.Anchor();studio.href='bambustudioopen://'+encodeURIComponent(asset+'&name=Mega.3mf');studio.click();
assert.equal(new URL(h.posts.at(-1).url).searchParams.get('action'),'open');assert.equal(h.navigations.length,0);
const foreign=new h.Anchor();foreign.href='https://example.com/a.3mf';foreign.click();assert.equal(h.navigations.at(-1),foreign.href);
for(const args of [['https://evil.test/en/models/123',false],[profile,true]]) {
 const blocked=harness(...args);const link=new blocked.Anchor();link.href=asset;link.click();
 assert.equal(blocked.posts.length,0);assert.equal(blocked.navigations.length,1);
}
h.c.location.href='https://makerworld.com/ko';h.c.history.pushState();h.flush();assert.equal(h.posts.at(-1).json,null);
console.log('PASS: embedded bridge sends one direct native handoff, preserves request-time profile context, prevents duplicate browser downloads, reports navigation, and excludes foreign origins/subframes (no network).');
