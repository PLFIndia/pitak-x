'use strict';

// Parity harness for the SHARED availability fixtures (ADR 0019 Decision 4,
// plan C.7; fixtures in test/fixtures/published_availability/).
//
// Usage:
//   node test/features/publish/published_availability_parity_harness.js \
//     <books.json path> <availability.json path | ->
//
// `-` means the site has no availability.json: its fetch answers 404.
//
// Runs the REAL bundled web viewer (`assets/publish/index.html`) in a VM
// context, exactly like published_catalogue_parity_harness.js, serving the
// two files from disk. The availability file is served as its exact bytes,
// so the viewer's own size cap, UTF-8 check and JSON rules all run. Then it
// prints ONE JSON object to stdout, and nothing else:
//
//   {"tags":[{"title":"…","tag":"available"|"out"|null}, …],
//    "summary":{"available":N,"tagged":M,"asOf":<number>|null},
//    "availableNow":["title", …]}
//
//  - tags: one entry per books[] row, in payload order, from the viewer's
//    availabilityTag() — the one per-item rule its badge and filter use;
//  - summary: the viewer's availabilitySummary();
//  - availableNow: the titles the viewer displays with the "Available now"
//    checkbox ticked and the default "Recently added" sort, groups
//    flattened (a series group contributes its issues in group order).
//
// A Dart test can compare this with the native reader over the same files,
// so the two viewers can never silently disagree about a tag. Any error
// exits non-zero (the message goes to stderr).

const assert = require('assert/strict');
const fs = require('fs');
const vm = require('vm');

function makeElement() {
  return {
    value: '',
    checked: false,
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

// The file's exact bytes as an ArrayBuffer, later exposed through the
// browser's streamed-body API. Node may hand back a view into a larger
// shared buffer, so only this file's slice is copied out.
function readArrayBuffer(path) {
  const bytes = new Uint8Array(fs.readFileSync(path));
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

async function main() {
  const [booksPath, availabilityPath] = process.argv.slice(2);
  assert.ok(
    booksPath && availabilityPath,
    'usage: node published_availability_parity_harness.js <books.json> <availability.json | ->',
  );
  const payload = JSON.parse(fs.readFileSync(booksPath, 'utf8'));
  const availabilityBytes =
    availabilityPath === '-' ? null : readArrayBuffer(availabilityPath);
  const html = fs.readFileSync('assets/publish/index.html', 'utf8');
  const scriptMatch = html.match(/<script>\n([\s\S]*?)<\/script>/);
  assert.ok(scriptMatch, 'viewer inline script must exist');

  const selectors = [
    '#root', '#q', '#sort', '#language', '#kind', '#availNow', '#availFilter', '#meta',
    '#availSummary', '#theme', '#eventsBanner',
  ];
  const elements = Object.fromEntries(selectors.map((s) => [s, makeElement()]));
  // The viewer's default sort is "Recently added" (see the parity harness:
  // `addedDate` is redacted, so the stable sort keeps the payload order).
  elements['#sort'].value = 'addedDate';
  const layoutButtons = ['table', 'card', 'grid'].map((layout) => {
    const button = makeElement();
    button.dataset.layout = layout;
    return button;
  });
  const document = {
    documentElement: makeElement(),
    visibilityState: 'visible',
    addEventListener() {},
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
  const unexpectedUrls = [];
  const context = {
    console,
    document,
    localStorage: { getItem() { return null; }, setItem() {} },
    matchMedia() { return { matches: false }; },
    // The 60 s re-check is never fired: one load is what this compares.
    setInterval() { return 1; },
    clearInterval() {},
    TextDecoder,
    async fetch(url) {
      if (url === 'books.json') {
        return { ok: true, status: 200, async json() { return payload; } };
      }
      if (url === 'availability.json') {
        if (availabilityBytes === null) return { ok: false, status: 404 };
        return {
          ok: true,
          status: 200,
          headers: { get() { return null; } },
          body: {
            getReader() {
              let sent = false;
              return {
                async read() {
                  if (sent) return { done: true };
                  sent = true;
                  // A fresh copy per response, like a real body stream.
                  return { done: false, value: new Uint8Array(availabilityBytes.slice(0)) };
                },
                async cancel() {},
              };
            },
          },
        };
      }
      if (url === 'events.html') return { ok: false, status: 404 };
      unexpectedUrls.push(url);
      return { ok: false, status: 404 };
    },
  };
  vm.runInNewContext(scriptMatch[1], context, {
    filename: 'assets/publish/index.html',
  });
  // Both fetches are fire-and-forget in the viewer; a few macrotask turns
  // let every resolved promise (fetch → body → parse → render) settle.
  for (let turn = 0; turn < 5; turn++) {
    await new Promise((resolve) => setImmediate(resolve));
  }

  assert.deepEqual(unexpectedUrls, [], 'viewer requested an unexpected URL');
  for (const name of ['availabilityTag', 'availabilitySummary', 'filterAndSort', 'groupIssues']) {
    assert.equal(typeof context[name], 'function', `viewer exposes ${name}`);
  }
  assert.ok(
    !elements['#root'].innerHTML.includes('Failed to load books.json'),
    elements['#root'].innerHTML,
  );

  const rows = Array.isArray(payload.books) ? payload.books : [];
  const tags = rows.map((row) => ({
    title: row.title,
    tag: context.availabilityTag(row),
  }));
  const summary = context.availabilitySummary();

  // Tick "Available now" through its real change handler (as a click would).
  const availNow = elements['#availNow'];
  assert.equal(typeof availNow.listeners.change, 'function', '#availNow must be wired');
  availNow.checked = true;
  availNow.listeners.change();
  const availableNow = [];
  for (const entry of context.groupIssues(context.filterAndSort())) {
    if (entry.group) {
      for (const issue of entry.group.issues) availableNow.push(issue.title);
    } else {
      availableNow.push(entry.item.title);
    }
  }

  process.stdout.write(JSON.stringify({
    tags,
    summary: {
      available: summary.available,
      tagged: summary.tagged,
      asOf: summary.asOf,
    },
    availableNow,
  }));
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
