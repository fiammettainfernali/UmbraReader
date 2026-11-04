import 'dart:convert';

/// The JavaScript channel every page in the browsers talks back through.
const kBrowserChannel = 'HawthorneBrowser';

/// Stops pop-ups and hides most ads. Runs ahead of the page's own scripts where
/// the phone allows it, and on page start where it doesn't.
///
/// It can't stop an ad's first request, since this web view gives no way to
/// refuse those, so it removes known ad frames and scripts as they appear and
/// hides their usual containers. A site that notices is what the switch is for.
const kAdBlockScript = r'''
(function () {
  if (window.__hcBlock) return;
  window.__hcBlock = true;
  var hosts = ['doubleclick.net','googlesyndication.com','googleadservices.com',
    'adservice.google','amazon-adsystem.com','adnxs.com','popads.net','popcash.net',
    'propellerads.com','adsterra.com','exoclick.com','juicyads.com','trafficjunky.net',
    'hilltopads.net','onclickads.net','pubmatic.com','rubiconproject.com','taboola.com',
    'outbrain.com','mgid.com','revcontent.com','adform.net','criteo.com','yllix.com',
    'clickadu.com','a-ads.com','bidvertiser.com','admaven.com','richads.com'];
  var isAd = function (url) {
    try {
      var host = new URL(url, location.href).hostname.toLowerCase();
      return hosts.some(function (h) { return host === h || host.endsWith('.' + h) || host.indexOf(h + '.') === 0; });
    } catch (e) { return false; }
  };
  var open = window.open;
  window.open = function (url) {
    try {
      var to = new URL(url || '', location.href);
      if (to.hostname.replace(/^www\./, '') !== location.hostname.replace(/^www\./, '')) return null;
    } catch (e) { return null; }
    return open.apply(window, arguments);
  };
  var sweep = function (root) {
    if (!root.querySelectorAll) return;
    root.querySelectorAll('iframe[src],script[src]').forEach(function (el) {
      if (isAd(el.src)) el.remove();
    });
  };
  var addStyle = function () {
    if (document.getElementById('hc-block-style') || !document.documentElement) return;
    var style = document.createElement('style');
    style.id = 'hc-block-style';
    style.textContent = 'ins.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],' +
      '[class*="adsbygoogle"],iframe[src*="doubleclick"],iframe[src*="googlesyndication"]' +
      '{display:none!important;height:0!important}';
    (document.head || document.documentElement).appendChild(style);
  };
  var start = function () {
    addStyle();
    sweep(document);
    new MutationObserver(function (changes) {
      changes.forEach(function (change) {
        change.addedNodes.forEach(function (node) {
          if (node.nodeType !== 1) return;
          if ((node.tagName === 'IFRAME' || node.tagName === 'SCRIPT') && node.src && isAd(node.src)) {
            node.remove();
          } else {
            sweep(node);
          }
        });
      });
    }).observe(document.documentElement, { childList: true, subtree: true });
  };
  if (document.documentElement) start();
  else document.addEventListener('readystatechange', start, { once: true });
})();
''';

/// Long-pressing a link asks the app what to do with it, because a web view
/// offers nothing of its own there.
const kLongPressScript = r'''
(function () {
  if (window.__hcPress) return;
  window.__hcPress = true;
  var timer = null, x = 0, y = 0, fired = 0;
  var post = function (message) {
    try { HawthorneBrowser.postMessage(JSON.stringify(message)); } catch (e) {}
  };
  var cancel = function () { clearTimeout(timer); timer = null; };
  document.addEventListener('touchstart', function (e) {
    cancel();
    if (e.touches.length !== 1 || !e.target.closest) return;
    if (e.target.closest('.hc-send')) return;
    var link = e.target.closest('a[href]');
    if (!link) return;
    x = e.touches[0].clientX; y = e.touches[0].clientY;
    timer = setTimeout(function () {
      fired = Date.now();
      // Without any send button that's inside the link, and by its cover's name
      // when a cover is all it has.
      var copy = link.cloneNode(true);
      copy.querySelectorAll('.hc-send').forEach(function (b) { b.remove(); });
      var image = link.querySelector('img');
      var text = (copy.textContent || '').replace(/\s+/g, ' ').trim() ||
        link.title || (image && image.alt) || '';
      post({ type: 'longpress', url: link.href, text: text.trim().slice(0, 120) });
    }, 520);
  }, { passive: true, capture: true });
  document.addEventListener('touchmove', function (e) {
    if (Math.abs(e.touches[0].clientX - x) + Math.abs(e.touches[0].clientY - y) > 12) cancel();
  }, { passive: true, capture: true });
  document.addEventListener('touchend', cancel, { passive: true, capture: true });
  document.addEventListener('touchcancel', cancel, { passive: true, capture: true });
  document.addEventListener('click', function (e) {
    if (Date.now() - fired < 800) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  document.addEventListener('contextmenu', function (e) {
    if (e.target.closest && e.target.closest('a[href]')) e.preventDefault();
  }, true);
})();
''';

/// Puts a send button beside each novel on a list page, so novels can be sent
/// without opening them and losing your place in the list.
///
/// [novelPath] is the pattern for a novel's address on this site. Each site lays
/// its pages out differently, but they all link to their novels, so this goes by
/// the links and not by the layout.
String sendButtonsScript(String novelPath) {
  return '''
(function (pattern) {
  if (window.__hcSend) { window.__hcSend.scan(); return; }
  var isNovel = new RegExp(pattern, 'i');
  var notNovel = /^\\/(contact|privacy|terms|dmca|about|disclaimer|faq|help|sitemap|index|home)[^\\/]*\\.html\$/i;
  var states = {};
  var labels = { none: '+', hold: '\\u2026', sent: '\\u2713', have: '\\u2713', wait: '\\u23F3' };
  var post = function (message) {
    try { HawthorneBrowser.postMessage(JSON.stringify(message)); } catch (e) {}
  };
  // Set on each button rather than in a style sheet: sites built to redraw
  // themselves throw away a sheet they didn't add.
  var shape = 'all:initial;display:inline-flex;align-items:center;justify-content:center;' +
    'flex:none;width:30px;height:30px;margin:0 8px 0 0;border-radius:50%;' +
    'font:800 20px/1 sans-serif;vertical-align:middle;cursor:pointer;' +
    '-webkit-tap-highlight-color:transparent;';
  var onCover = 'position:absolute;top:6px;right:6px;margin:0;z-index:9999;';
  var glow = 'box-shadow:0 0 10px rgba(229,18,31,.65);';
  var looks = {
    none: 'background:#e5121f;color:#fff;' + glow,
    hold: 'background:#5a0710;color:#fff;' + glow,
    wait: 'background:#5a0710;color:#fff;' + glow,
    sent: 'background:#fff;color:#a50c16;' + glow,
    have: 'background:#3a2326;color:#cdbcbd;box-shadow:none;'
  };
  var paint = function (button, state) {
    button.dataset.state = state;
    button.textContent = labels[state] || '+';
    button.style.cssText = shape + (button.classList.contains('over') ? onCover : '') +
      (looks[state] || looks.none);
  };
  var mark = function (url, state) {
    states[url] = state;
    document.querySelectorAll('.hc-send').forEach(function (button) {
      if (button.dataset.url === url) paint(button, state);
    });
  };
  var titleOf = function (link) {
    // Without the button, which can be sitting inside the link.
    var copy = link.cloneNode(true);
    copy.querySelectorAll('.hc-send').forEach(function (b) { b.remove(); });
    var text = (copy.textContent || '').replace(/\\s+/g, ' ').trim();
    if (text) return text.slice(0, 160);
    var image = link.querySelector('img');
    return ((image && image.alt) || link.title || '').trim().slice(0, 160);
  };
  var attach = function (link, url) {
    var button = document.createElement('span');
    button.className = 'hc-send';
    button.dataset.url = url;
    button.setAttribute('role', 'button');
    button.setAttribute('aria-label', 'Send to your computer');
    button.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      post({ type: 'send', url: url, title: titleOf(link) });
    }, true);
    if (link.querySelector('img')) {
      // On the cover, clear of any caption laid over its bottom edge.
      button.classList.add('over');
      // An inline link has no box to sit in. Changing how it's laid out can
      // collapse a cover sized to fill it, so this uses what's around it instead.
      var inline = getComputedStyle(link).display === 'inline';
      var holder = inline ? link.parentElement : link;
      if (getComputedStyle(holder).position === 'static') holder.style.position = 'relative';
      if (inline) link.after(button);
      else link.appendChild(button);
    } else {
      // Ahead of the title: a list row cuts a long title off, and anything
      // after it along with the title.
      link.parentNode.insertBefore(button, link);
    }
    paint(button, states[url] || 'none');
  };
  var hasCover = function (link) {
    var image = link.querySelector('img');
    return !!image && image.getBoundingClientRect().width >= 60;
  };
  var scan = function () {
    var found = {};
    document.querySelectorAll('a[href]').forEach(function (link) {
      if (link.origin !== location.origin) return;
      var path = link.pathname;
      if (!isNovel.test(path) || notNovel.test(path) || path === location.pathname) return;
      if (link.closest('nav,header,footer')) return;
      var url = link.origin + path;
      (found[url] = found[url] || []).push(link);
    });
    var placed = {};
    document.querySelectorAll('.hc-send').forEach(function (b) { placed[b.dataset.url] = true; });
    var fresh = [];
    Object.keys(found).forEach(function (url) {
      if (placed[url]) return;
      var links = found[url];
      var best = links.filter(hasCover)[0] ||
        links.filter(function (l) { return (l.innerText || '').trim().length > 1 && !l.querySelector('img'); })[0];
      attach(best || links[0], url);
      fresh.push(url);
    });
    if (fresh.length) post({ type: 'links', urls: fresh });
  };
  window.__hcSend = { scan: scan };
  window.__hcMark = mark;
  scan();
  var waiting = null;
  // Not put off by further changes: on a page that never stops changing, that
  // would put it off for good, and a site that redraws its list needs it most.
  new MutationObserver(function () {
    if (waiting) return;
    waiting = setTimeout(function () { waiting = null; scan(); }, 400);
  }).observe(document.body, { childList: true, subtree: true });
})(${jsonEncode(novelPath)});
''';
}

/// Sets a send button's look, once the page has its buttons.
String markSendButton(String url, String state) {
  return 'window.__hcMark&&window.__hcMark(${jsonEncode(url)},'
      '${jsonEncode(state)});';
}
