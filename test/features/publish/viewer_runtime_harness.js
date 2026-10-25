'use strict';

// Dependency-free DOM harness for the real bundled viewer. Flutter's test
// runner invokes this with Node and passes a books.json fixture produced by
// the Dart redactor, so the test exercises the actual publish/viewer boundary.
const assert = require('assert/strict');
const fs = require('fs');
const vm = require('vm');

function makeElement() {
  return {
    value: '',
    innerHTML: '',
    textContent: '',
    className: '',
    style: {},
    dataset: {},
    attributes: {},
    listeners: {},
    classList: { add() {}, toggle() {} },
    addEventListener(name, callback) {
      this.listeners[name] = callback;
    },
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    },
    getAttribute(name) {
      return this.attributes[name] ?? null;
    },
  };
}

async function main() {
  const payloadPath = process.argv[2];
  assert.ok(payloadPath, 'usage: node viewer_runtime_harness.js books.json');
  const payload = JSON.parse(fs.readFileSync(payloadPath, 'utf8'));
  const html = fs.readFileSync('assets/publish/index.html', 'utf8');
  const scriptMatch = html.match(/<script>\n([\s\S]*?)<\/script>/);
  assert.ok(scriptMatch, 'viewer inline script must exist');

  const elements = Object.fromEntries(
    ['#root', '#q', '#sort', '#language', '#kind', '#meta', '#theme', '#eventsBanner']
      .map((selector) => [selector, makeElement()]),
  );
  elements['#sort'].value = 'addedDate';
  const buttons = ['table', 'card', 'grid'].map((layout) => {
    const button = makeElement();
    button.dataset.layout = layout;
    return button;
  });
  const documentElement = makeElement();
  const document = {
    documentElement,
    querySelector(selector) {
      const element = elements[selector];
      assert.ok(element, `unexpected document.querySelector(${selector})`);
      return element;
    },
    querySelectorAll(selector) {
      assert.equal(selector, 'button[data-layout]');
      return buttons;
    },
  };
  const storage = new Map();
  const context = {
    console,
    document,
    localStorage: {
      getItem(key) { return storage.get(key) ?? null; },
      setItem(key, value) { storage.set(key, String(value)); },
    },
    matchMedia() { return { matches: false }; },
    async fetch(url) {
      if (url === 'events.html') return { ok: false };
      assert.equal(url, 'books.json');
      return { ok: true, async json() { return payload; } };
    },
  };
  vm.runInNewContext(scriptMatch[1], context, {
    filename: 'assets/publish/index.html',
  });
  // load() is intentionally fire-and-forget in the viewer. One macrotask turn
  // flushes its resolved fetch/json promises without changing production code.
  await new Promise((resolve) => setImmediate(resolve));

  const root = elements['#root'];
  const escapedTitle = 'Other &lt;img src=x onerror=alert(2)&gt; &amp; &quot;quoted&quot;';
  const rawTitle = 'Other <img src=x onerror=alert(2)> & "quoted"';
  const excludedValues = [
    'OTHER_EXCLUDED_TRANSLITERATION',
    'OTHER_EXCLUDED_AUTHOR',
    'OTHER_EXCLUDED_ISBN',
    'OTHER_EXCLUDED_PUBLISHER',
    'OTHER_EXCLUDED_GENRE',
    'OTHER_EXCLUDED_DESCRIPTION',
    '19497',
  ];

  for (const layout of ['table', 'card', 'grid']) {
    if (layout !== 'table') {
      const button = buttons.find((candidate) => candidate.dataset.layout === layout);
      assert.ok(button.listeners.click, `${layout} button must be wired`);
      button.listeners.click();
    }
    assert.equal(root.className, `layout-${layout}`);
    const rendered = root.innerHTML;
    assert.ok(rendered.length > 0, `${layout} must render the catalogue`);
    assert.ok(!rendered.includes('Failed to load books.json'), rendered);
    assert.ok(rendered.includes(escapedTitle), `${layout}: Other title must be escaped`);
    assert.ok(!rendered.includes(rawTitle), `${layout}: raw Other HTML must not render`);
    for (const value of excludedValues) {
      assert.ok(!rendered.includes(value), `${layout}: excluded Other value rendered: ${value}`);
    }
    assert.ok(!rendered.includes('avail-available'), `${layout}: Other availability leaked`);
    assert.ok(!rendered.includes('avail-out'), `${layout}: Other availability leaked`);
    for (const placeholder of ['ISBN null', 'ISBN undefined', '>null<', '>undefined<']) {
      assert.ok(!rendered.includes(placeholder), `${layout}: placeholder rendered: ${placeholder}`);
    }
    assert.ok(rendered.includes('Above 10'), `${layout}: Other age group must remain public`);

    const seriesIndex = rendered.indexOf('Series &lt;One&gt; &amp; &quot;One&quot;');
    const newerIndex = rendered.indexOf('Newer issue');
    const olderIndex = rendered.indexOf('Older issue');
    assert.ok(seriesIndex >= 0, `${layout}: escaped series heading must render`);
    assert.ok(seriesIndex < newerIndex, `${layout}: series heading must precede issues`);
    assert.ok(newerIndex < olderIndex, `${layout}: newest issue must sort first`);
    assert.ok(!rendered.includes('Series <One>'), `${layout}: raw series HTML must not render`);
    assert.ok(rendered.includes('Publisher &lt;Two&gt;'), `${layout}: series metadata must escape`);
    assert.ok(rendered.includes('Ordinary book'), `${layout}: ordinary books must still render`);
    if (layout !== 'grid') {
      assert.ok(rendered.includes('Visible author'), `${layout}: book author must remain public`);
      assert.ok(rendered.includes('VISIBLE_ISBN'), `${layout}: book ISBN must remain public`);
      assert.ok(rendered.includes('Visible publisher') || layout === 'table',
        `${layout}: book publisher must remain public in cards`);
      assert.ok(rendered.includes('Visible transliteration'),
        `${layout}: book transliteration must remain public`);
    } else {
      const hostileCover = payload.books[0].coverUrl;
      assert.ok(!rendered.includes(hostileCover), 'grid: raw cover attribute must not render');
      assert.ok(!rendered.includes('onerror="alert(1)'), 'grid: attribute injection must not render');
      assert.ok(rendered.includes('cover.jpg&quot; onerror=&quot;alert(1)'),
        'grid: cover URL attribute characters must be escaped');
    }
  }

  console.log('viewer runtime checks passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
