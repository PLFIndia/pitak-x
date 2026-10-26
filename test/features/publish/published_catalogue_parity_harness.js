'use strict';

// Parity harness for the SHARED published-catalogue fixture (viewer plan S6).
//
// Runs the REAL bundled web viewer (`assets/publish/index.html`) over the same
// `books.json` fixture the native reader/query tests use, then prints the
// display order it computed as JSON:
//
//   [{"item":"Title"}, {"group":"seriesUid","issues":["Title",…]}, …]
//
// The Dart test compares that list with `PublishedQueryEngine.apply`, so the
// native grouping/order can never silently drift from the viewer users see.
//
// The DOM harness is the one already used by `viewer_runtime_harness.js`:
// dependency-free stubs, the viewer's own inline script in a VM context, one
// macrotask turn to flush its fire-and-forget load().

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
  assert.ok(payloadPath, 'usage: node published_catalogue_parity_harness.js books.json');
  const payload = JSON.parse(fs.readFileSync(payloadPath, 'utf8'));
  const html = fs.readFileSync('assets/publish/index.html', 'utf8');
  const scriptMatch = html.match(/<script>\n([\s\S]*?)<\/script>/);
  assert.ok(scriptMatch, 'viewer inline script must exist');

  const selectors = ['#root', '#q', '#sort', '#language', '#kind', '#meta', '#theme', '#eventsBanner'];
  const elements = Object.fromEntries(selectors.map((s) => [s, makeElement()]));
  // The viewer's default sort is "Recently added"; `addedDate` is REDACTED from
  // every published row, so its comparator is 0 for all rows and the stable
  // sort keeps the payload order — exactly the native "Published order".
  elements['#sort'].value = 'addedDate';
  const layoutButtons = ['table', 'card', 'grid'].map((layout) => {
    const button = makeElement();
    button.dataset.layout = layout;
    return button;
  });
  const document = {
    documentElement: makeElement(),
    querySelector(selector) {
      const element = elements[selector];
      assert.ok(element, `unexpected document.querySelector(${selector})`);
      return element;
    },
    querySelectorAll(selector) {
      assert.equal(selector, 'button[data-layout]');
      return layoutButtons;
    },
  };
  const context = {
    console,
    document,
    localStorage: { getItem() { return null; }, setItem() {} },
    matchMedia() { return { matches: false }; },
    async fetch() {
      return { ok: true, async json() { return payload; } };
    },
  };
  vm.runInNewContext(scriptMatch[1], context, {
    filename: 'assets/publish/index.html',
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(typeof context.filterAndSort, 'function', 'viewer exposes filterAndSort');
  assert.equal(typeof context.groupIssues, 'function', 'viewer exposes groupIssues');

  const display = context.groupIssues(context.filterAndSort());
  const out = display.map((entry) =>
    entry.group
      ? { group: entry.group.series.title, issues: entry.group.issues.map((i) => i.title) }
      : { item: entry.item.title },
  );
  process.stdout.write(JSON.stringify(out));
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
