const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('Resources/BrowserNavigation.js', 'utf8');
function fixture({page = 'https://makerworld.com/en/@me/collections/models', dialogLinks, href, download = false} = {}) {
  let listener;
  const messages = [];
  class Element {
    closest(selector) {
      if (selector === 'a[href]') return href ? {href, hasAttribute: () => download} : null;
      return dialogLinks ? {querySelectorAll: () => dialogLinks.map(href => ({href}))} : null;
    }
  }
  const context = {URL, Set, Element, location: new URL(page), document: {addEventListener: (_, callback) => listener = callback}, window: {webkit: {messageHandlers: {makerDockNavigation: {postMessage: m => messages.push(m)}}}}};
  vm.runInNewContext(source, context);
  return {messages, click(options = {}) {
    const event = {isTrusted:true, target:new Element(), metaKey:false, shiftKey:false, prevented:false, stopped:false,
      preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }, ...options};
    listener(event); return event;
  }};
}
let f = fixture({dialogLinks:['https://makerworld.com/ko/models/123-hook?token=discarded#profileId-9','https://makerworld.com/en/models/123-hook']});
f.click(); assert.equal(f.messages[0].pageURL, 'https://makerworld.com/ko/models/123-hook');
f = fixture({page:'https://makerworld.com/en/models/1-underneath', dialogLinks:['https://makerworld.com/en/models/2','https://makerworld.com/en/models/3']});
f.click(); assert.equal(f.messages[0].pageURL, null, 'Ambiguous overlays must not label the underlying model');
f = fixture({href:'https://makerworld.com/en/models/456-model'});
let e = f.click({metaKey:true}); assert.equal(e.prevented,true); assert.equal(e.stopped,true); assert.equal(f.messages[1].kind,'tab'); assert.equal(f.messages[1].foreground,false);
f = fixture({href:'https://makerworld.com/en/models/456-model'}); f.click({metaKey:true,shiftKey:true}); assert.equal(f.messages[1].foreground,true);
f = fixture({href:'https://makerworld.com/en/models/456-model'}); e = f.click(); assert.equal(e.prevented,false); assert.equal(f.messages.length,1);
f = fixture({href:'https://makerworld.com/en/file.3mf',download:true}); e=f.click({metaKey:true}); assert.equal(e.prevented,false);
f = fixture({href:'https://makerworld.com.evil.test/en/models/456'}); e=f.click({metaKey:true}); assert.equal(e.prevented,false); assert.equal(f.messages.length,1);
f=fixture(); f.click({isTrusted:false}); assert.equal(f.messages.length,0);
f=fixture({page:'https://evil.test',href:'https://makerworld.com/en/models/456'}); f.click({metaKey:true}); assert.equal(f.messages.length,0);
console.log('Navigation gestures: 9 scenarios passed');
