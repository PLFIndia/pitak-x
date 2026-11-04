'use strict';

// Web-only behaviour checks for the bundled viewer's availability file
// (viewerVersion 8; ADR 0019 Decision 4, plan C.7).
//
// published_availability_parity_harness.js proves the web and native viewers
// pick the same TAG for every item. This harness covers what only the web
// page does: the 60 s re-check and its visibility rule, the request shape
// (cache: "no-cache", never a ?query), what a re-check does after a 404, an
// ignored file or a network error, the hostile-input limits at their exact
// boundaries, and the labels, "Available now" filter and summary line.
//
// Like viewer_runtime_harness.js it runs the REAL inline viewer script in a
// dependency-free VM context. Timers are recorded and fired by hand, so
// nothing here waits for real time. Each check starts a fresh viewer.
// Prints "ok - <check>" per check and, last, "viewer availability checks
// passed"; any failure exits non-zero (viewer_availability_test.dart).

const assert = require('assert/strict');
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync('assets/publish/index.html', 'utf8');
const scriptMatch = html.match(/<script>\n([\s\S]*?)<\/script>/);
assert.ok(scriptMatch, 'viewer inline script must exist');
const VIEWER_SCRIPT = scriptMatch[1];

const MAX_BYTES = 1048576; // the viewer's 1 MiB cap
const KEY_SET = '5e0c1d2b3a497f68';
const LISTED_KEY = 'aaaaaaaaaaaaaaa1';
const OTHER_KEY = 'aaaaaaaaaaaaaaa3';

// A promise the viewer forgets about must never reject unhandled.
const unhandledRejections = [];
process.on('unhandledRejection', (reason) => unhandledRejections.push(reason));

// The catalogue every check uses unless it says otherwise. The comments give
// each row's tag WITH the file below / WITHOUT any file (inline tags only).
function catalogue(overrides = {}) {
  return {
    schemaVersion: 1,
    exportedAt: 1,
    keySet: KEY_SET,
    books: [
      // out / available
      { title: 'Listed book', kind: 'book', key: LISTED_KEY, availability: 'available' },
      // available / out
      { title: 'Unlisted book', kind: 'book', key: 'aaaaaaaaaaaaaaa2', availability: 'out' },
      // available / available (no key: always the inline tag)
      { title: 'Unkeyed book', kind: 'book', availability: 'available' },
      // available / none
      { title: 'Untagged keyed book', kind: 'book', key: 'aaaaaaaaaaaaaaa4' },
      // none / none: Other never carries a tag, whatever the payload says
      { title: 'Other row', kind: 'other', key: OTHER_KEY, availability: 'out' },
    ],
    ...overrides,
  };
}
const TAGS_WITH_FILE = ['out', 'available', 'available', 'available', null];
const TAGS_INLINE = ['available', 'out', 'available', null, null];

// A valid availability.json (as text) listing the first and the Other row.
function fileText(fields = {}) {
  return JSON.stringify({
    schemaVersion: 1,
    keySet: KEY_SET,
    asOf: Date.now() - 60000, // a minute ago: plausible, so a time is shown
    out: [LISTED_KEY, OTHER_KEY],
    ...fields,
  });
}

function toArrayBuffer(bytes) {
  const view = new Uint8Array(bytes);
  return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
}

// ---- Answers the fake server gives for availability.json ----
const notFound = () => ({ ok: false, status: 404 });
const networkError = () => { throw new TypeError('Failed to fetch'); };
function bytesAnswer(bytes, { chunkSize = 16384, declaredLength } = {}) {
  const state = { cancelled: false, reads: 0 };
  const answer = () => ({
    ok: true,
    status: 200,
    headers: {
      get(name) {
        return name.toLowerCase() === 'content-length' && declaredLength !== undefined
          ? String(declaredLength)
          : null;
      },
    },
    body: {
      getReader() {
        let offset = 0;
        return {
          async read() {
            state.reads++;
            if (offset >= bytes.length) return { done: true };
            const end = Math.min(offset + chunkSize, bytes.length);
            const value = bytes.subarray(offset, end);
            offset = end;
            return { done: false, value };
          },
          async cancel() { state.cancelled = true; },
        };
      },
    },
    async arrayBuffer() { throw new Error('unbounded arrayBuffer() was called'); },
  });
  answer.state = state;
  return answer;
}
const textAnswer = (text) => bytesAnswer(Buffer.from(text, 'utf8'));

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

// Lets every resolved promise (fetch → body → parse → render) run.
async function settle() {
  for (let turn = 0; turn < 5; turn++) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}

// Starts the real viewer script. `answer` decides what availability.json
// returns; `viewer.setAnswer` swaps it for later re-checks.
function startViewer({ payload = catalogue(), answer }) {
  const elements = Object.fromEntries(
    [
      '#root', '#q', '#sort', '#language', '#kind', '#availNow', '#availFilter', '#meta',
      '#availSummary', '#theme', '#eventsBanner',
    ].map((selector) => [selector, makeElement()]),
  );
  elements['#sort'].value = 'addedDate';
  const buttons = ['table', 'card', 'grid'].map((layout) => {
    const button = makeElement();
    button.dataset.layout = layout;
    return button;
  });
  const documentListeners = {};
  const document = {
    documentElement: makeElement(),
    visibilityState: 'visible',
    addEventListener(name, callback) {
      documentListeners[name] = callback;
    },
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
  const intervals = [];
  const fetches = [];
  let currentAnswer = answer;
  const context = {
    console,
    document,
    localStorage: { getItem() { return null; }, setItem() {} },
    matchMedia() { return { matches: false }; },
    setInterval(callback, milliseconds) {
      intervals.push({ callback, milliseconds });
      return intervals.length;
    },
    clearInterval() {},
    TextDecoder,
    async fetch(url, options) {
      fetches.push({ url, options });
      if (url === 'events.html') return { ok: false, status: 404 };
      if (url === 'books.json') {
        return { ok: true, status: 200, async json() { return payload; } };
      }
      if (url === 'availability.json') return currentAnswer();
      // Anything else (e.g. "availability.json?t=…") is a bug; the request
      // checks below fail on it.
      return { ok: false, status: 404 };
    },
  };
  vm.runInNewContext(VIEWER_SCRIPT, context, { filename: 'assets/publish/index.html' });

  return {
    context,
    elements,
    document,
    documentListeners,
    intervals,
    fetches,
    payload,
    setAnswer(next) { currentAnswer = next; },
    // Every request that was not for books.json or the events probe.
    availabilityRequests() {
      return fetches.filter((f) => f.url !== 'books.json' && f.url !== 'events.html');
    },
    tags() { return payload.books.map((row) => context.availabilityTag(row)); },
    rendered() { return elements['#root'].innerHTML; },
    summaryText() { return elements['#availSummary'].textContent; },
    async fireInterval() {
      assert.equal(intervals.length, 1, 'exactly one re-check timer');
      intervals[0].callback();
      await settle();
    },
    async fireVisibilityChange(state) {
      document.visibilityState = state;
      assert.equal(typeof documentListeners.visibilitychange, 'function');
      documentListeners.visibilitychange();
      await settle();
    },
    clickLayout(layout) {
      const button = buttons.find((b) => b.dataset.layout === layout);
      button.listeners.click();
    },
  };
}

async function started(options) {
  const viewer = startViewer(options);
  await settle();
  assert.ok(!viewer.rendered().includes('Failed to load books.json'), viewer.rendered());
  return viewer;
}

// Valid JSON padded with trailing spaces (legal JSON whitespace) to exactly
// `size` bytes.
function paddedTo(size) {
  const text = fileText();
  assert.ok(text.length < size);
  return text + ' '.repeat(size - Buffer.byteLength(text, 'utf8'));
}

// A valid file whose deepest nesting is exactly `depth`: the root object is
// level 1, and an extra field holds depth − 1 nested arrays.
function nestedTo(depth) {
  const inner = '['.repeat(depth - 1) + ']'.repeat(depth - 1);
  return fileText().slice(0, -1) + ',"extra":' + inner + '}';
}

// ---- The checks ----
const checks = {
  async 'both files are requested at once, before either answers'() {
    const viewer = startViewer({ answer: textAnswer(fileText()) });
    // Nothing has settled yet: both requests already left.
    const urls = viewer.fetches.map((f) => f.url);
    assert.ok(urls.includes('books.json'), urls.join());
    assert.ok(urls.includes('availability.json'), urls.join());
    await settle();
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
  },

  async 'labels read Available / Not available; "All out" never renders'() {
    for (const answer of [textAnswer(fileText()), notFound]) {
      const viewer = await started({ answer });
      for (const layout of ['table', 'card', 'grid']) {
        viewer.clickLayout(layout);
        const rendered = viewer.rendered();
        assert.equal(viewer.elements['#root'].className, `layout-${layout}`);
        assert.ok(rendered.includes('<span class="avail avail-out">Not available</span>'),
          `${layout}: "Not available" label`);
        assert.ok(rendered.includes('<span class="avail avail-available">Available</span>'),
          `${layout}: "Available" label`);
        assert.ok(!rendered.includes('All out'), `${layout}: the retired label rendered`);
      }
    }
  },

  async 'an Other row with an inline "out" and a listed key shows no tag'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    const other = viewer.payload.books[4];
    assert.equal(viewer.context.availabilityTag(other), null);
    viewer.elements['#kind'].value = 'other';
    viewer.elements['#kind'].listeners.change();
    for (const layout of ['table', 'card', 'grid']) {
      viewer.clickLayout(layout);
      const rendered = viewer.rendered();
      assert.ok(rendered.includes('Other row'), `${layout}: the Other row renders`);
      assert.ok(!rendered.includes('avail-available'), `${layout}: Other tagged Available`);
      assert.ok(!rendered.includes('avail-out'), `${layout}: Other tagged Not available`);
    }
  },

  async 'exactly one 60 s re-check timer is registered'() {
    const viewer = await started({ answer: notFound });
    assert.equal(viewer.intervals.length, 1);
    assert.equal(viewer.intervals[0].milliseconds, 60000);
  },

  async 're-checks only while visible, with cache "no-cache" and no ?query'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    assert.equal(viewer.availabilityRequests().length, 1, 'the first load');

    viewer.document.visibilityState = 'hidden';
    await viewer.fireInterval();
    assert.equal(viewer.availabilityRequests().length, 1, 'a hidden page made a request');

    viewer.document.visibilityState = 'visible';
    await viewer.fireInterval();
    const requests = viewer.availabilityRequests();
    assert.equal(requests.length, 2, 'a visible page re-checks exactly once');
    for (const request of requests) {
      assert.equal(request.url, 'availability.json');
      assert.ok(!request.url.includes('?'), 'no query-string cache-buster');
      assert.equal(request.options.cache, 'no-cache');
    }
  },

  async 'becoming visible re-checks once; becoming hidden does not'() {
    const viewer = await started({ answer: notFound });
    await viewer.fireVisibilityChange('hidden');
    assert.equal(viewer.availabilityRequests().length, 1);
    await viewer.fireVisibilityChange('visible');
    assert.equal(viewer.availabilityRequests().length, 2);
    assert.equal(viewer.availabilityRequests()[1].url, 'availability.json');
  },

  async 'a re-check answering 404 drops the file: inline tags return'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
    viewer.setAnswer(notFound);
    await viewer.fireInterval();
    assert.deepEqual(viewer.tags(), TAGS_INLINE);
    assert.equal(viewer.summaryText(), '2 of 3 available', 'no file: no time either');
    // The list was redrawn with the inline tag of the first row.
    assert.ok(viewer.rendered().includes('>Listed book <span class="avail avail-available">'));
  },

  async 'a re-check finding an ignored file drops the file too'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    viewer.setAnswer(textAnswer(fileText({ schemaVersion: 2 })));
    await viewer.fireInterval();
    assert.deepEqual(viewer.tags(), TAGS_INLINE);
  },

  async 'a re-check whose request fails keeps the last accepted file'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    viewer.setAnswer(networkError);
    await viewer.fireInterval();
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
    assert.ok(/^3 of 4 available · updated /.test(viewer.summaryText()));
  },

  async 'a first load whose request fails means no file, until a re-check'() {
    const viewer = await started({ answer: networkError });
    assert.deepEqual(viewer.tags(), TAGS_INLINE);
    viewer.setAnswer(textAnswer(fileText()));
    await viewer.fireInterval();
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
  },

  async '500 and 429 re-checks preserve the last accepted file'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    for (const status of [500, 429]) {
      viewer.setAnswer(() => ({ ok: false, status }));
      await viewer.fireInterval();
      assert.deepEqual(viewer.tags(), TAGS_WITH_FILE, `HTTP ${status}`);
    }
  },

  async 'a response without streaming is unreachable, never arrayBuffer-read'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    const withoutStream = textAnswer(fileText())();
    withoutStream.body = null;
    viewer.setAnswer(() => withoutStream);
    await viewer.fireInterval();
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
  },

  async 'an honestly declared over-cap length is refused before body reads'() {
    const answer = bytesAnswer(Buffer.from(fileText()), { declaredLength: MAX_BYTES + 1 });
    const viewer = startViewer({ answer });
    let parseCalls = 0;
    const parse = viewer.context.parseAvailability;
    viewer.context.parseAvailability = (buffer) => { parseCalls++; return parse(buffer); };
    await settle();
    assert.equal(answer.state.reads, 0);
    assert.equal(parseCalls, 0);
    assert.deepEqual(viewer.tags(), TAGS_INLINE);
  },

  async 'a streamed body over 1 MiB is cancelled and never parsed'() {
    const overCap = Buffer.from(paddedTo(MAX_BYTES + 1), 'utf8');
    const answer = bytesAnswer(overCap, { chunkSize: MAX_BYTES - 1 });
    const viewer = startViewer({ answer });
    let parseCalls = 0;
    const parse = viewer.context.parseAvailability;
    viewer.context.parseAvailability = (buffer) => { parseCalls++; return parse(buffer); };
    await settle();
    assert.equal(answer.state.cancelled, true);
    assert.equal(parseCalls, 0);
    assert.deepEqual(viewer.tags(), TAGS_INLINE);
  },

  async 'a body over 1 MiB is ignored; a valid file at the cap is used'() {
    const atCap = Buffer.from(paddedTo(MAX_BYTES), 'utf8');
    const overCap = Buffer.from(paddedTo(MAX_BYTES + 1), 'utf8');
    assert.equal(atCap.length, 1048576);
    assert.equal(overCap.length, 1048577);

    const used = await started({ answer: bytesAnswer(atCap) });
    assert.deepEqual(used.tags(), TAGS_WITH_FILE, 'a 1,048,576-byte file must be used');
    const ignored = await started({ answer: bytesAnswer(overCap) });
    assert.deepEqual(ignored.tags(), TAGS_INLINE, 'a 1,048,577-byte file must be ignored');
  },

  async 'nesting deeper than 16 is ignored; brackets inside strings do not count'() {
    const depth16 = await started({ answer: textAnswer(nestedTo(16)) });
    assert.deepEqual(depth16.tags(), TAGS_WITH_FILE, 'depth 16 is allowed');
    const depth17 = await started({ answer: textAnswer(nestedTo(17)) });
    assert.deepEqual(depth17.tags(), TAGS_INLINE, 'depth 17 must be ignored');

    // 40 brackets inside a string (after an escaped quote) are text, not
    // nesting, exactly as in the app's JsonNestingDepth.
    const quoted = fileText({ note: '"' + '['.repeat(40) });
    const viewer = await started({ answer: textAnswer(quoted) });
    assert.deepEqual(viewer.tags(), TAGS_WITH_FILE);
  },

  async 'invalid UTF-8 is ignored; valid non-ASCII text is fine'() {
    const head = fileText().slice(0, -1) + ',"note":"';
    const invalid = Buffer.concat([Buffer.from(head), Buffer.from([0xff]), Buffer.from('"}')]);
    const bad = await started({ answer: bytesAnswer(invalid) });
    assert.deepEqual(bad.tags(), TAGS_INLINE);
    const good = await started({ answer: textAnswer(fileText({ note: 'ಕನ್ನಡ ಪುಸ್ತಕ' })) });
    assert.deepEqual(good.tags(), TAGS_WITH_FILE);
  },

  async 'the file applies only when both keySets are valid and equal'() {
    const answer = textAnswer(fileText());
    const noKeySet = await started({ payload: catalogue({ keySet: undefined }), answer });
    assert.deepEqual(noKeySet.tags(), TAGS_INLINE);
    const otherKeySet = await started({ payload: catalogue({ keySet: '0000000000000000' }), answer });
    assert.deepEqual(otherKeySet.tags(), TAGS_INLINE);
    const upperCase = await started({ payload: catalogue({ keySet: KEY_SET.toUpperCase() }), answer });
    assert.deepEqual(upperCase.tags(), TAGS_INLINE);
  },

  async 'the Available now checkbox filters the rendered list'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    const checkbox = viewer.elements['#availNow'];
    assert.equal(typeof checkbox.listeners.change, 'function', '#availNow must be wired');
    checkbox.checked = true;
    checkbox.listeners.change();
    // The table puts each title right after its cell's ">", so ">Listed
    // book" cannot be confused with ">Unlisted book".
    const rendered = viewer.rendered();
    for (const title of ['Unlisted book', 'Unkeyed book', 'Untagged keyed book']) {
      assert.ok(rendered.includes('>' + title), `${title} is available and must show`);
    }
    for (const title of ['Listed book', 'Other row']) {
      assert.ok(!rendered.includes('>' + title), `${title} must be filtered out`);
    }
    assert.equal(viewer.elements['#meta'].textContent, '3 of 5 items');

    checkbox.checked = false;
    checkbox.listeners.change();
    assert.equal(viewer.elements['#meta'].textContent, '5 of 5 items');
  },

  async 'the summary counts every item and shows a time only when plausible'() {
    const viewer = await started({ answer: textAnswer(fileText()) });
    const summary = viewer.context.availabilitySummary();
    assert.equal(summary.available, 3);
    assert.equal(summary.tagged, 4);
    assert.equal(typeof summary.asOf, 'number');
    assert.ok(/^3 of 4 available · updated .+/.test(viewer.summaryText()), viewer.summaryText());

    // The counts ignore the filters: they describe the whole library.
    viewer.elements['#availNow'].checked = true;
    viewer.elements['#availNow'].listeners.change();
    assert.ok(viewer.summaryText().startsWith('3 of 4 available'));

    const future = await started({
      answer: textAnswer(fileText({ asOf: Date.now() + 2 * 86400000 })),
    });
    assert.equal(future.summaryText(), '3 of 4 available', 'an implausible asOf shows no time');
    assert.equal(future.context.availabilitySummary().asOf, null);

    const untagged = catalogue({
      books: [
        { title: 'Plain book', kind: 'book' },
        { title: 'Plain other', kind: 'other', availability: 'out' },
      ],
    });
    const nothing = await started({ payload: untagged, answer: notFound });
    assert.equal(nothing.summaryText(), '', 'nothing tagged: empty summary');
    assert.deepEqual(
      JSON.parse(JSON.stringify(nothing.context.availabilitySummary())),
      { available: 0, tagged: 0, asOf: null },
    );
  },

  async 'Available now is offered only while something is tagged'() {
    const tagged = await started({ answer: textAnswer(fileText()) });
    assert.equal(tagged.elements['#availFilter'].hidden, false, 'tags: offered');

    const untagged = await started({
      payload: catalogue({ books: [{ title: 'Plain book', kind: 'book' }] }),
      answer: notFound,
    });
    assert.equal(untagged.elements['#availFilter'].hidden, true, 'no tags: hidden');
    // A ticked box stays visible, so it can always be unticked again.
    untagged.elements['#availNow'].checked = true;
    untagged.elements['#availNow'].listeners.change();
    assert.equal(untagged.elements['#availFilter'].hidden, false, 'ticked: kept');
  },

  async 'the newer-schema notice survives the item count'() {
    const viewer = await started({
      payload: catalogue({ schemaVersion: 2 }),
      answer: notFound,
    });
    const meta = viewer.elements['#meta'].textContent;
    assert.ok(meta.startsWith('5 of 5 items · '), meta);
    assert.ok(meta.includes('created by a newer Pitak'), meta);
  },

  async 'an unchanged re-check refreshes the summary but not the list'() {
    const viewer = await started({ answer: textAnswer(fileText({ asOf: 1761984300000 })) });
    viewer.elements['#root'].innerHTML = 'UNTOUCHED';
    viewer.elements['#availSummary'].textContent = 'STALE';
    await viewer.fireInterval();
    assert.equal(viewer.rendered(), 'UNTOUCHED', 'the same file must not redraw the list');
    assert.ok(viewer.summaryText().startsWith('3 of 4 available · updated '));

    // A changed file does redraw it.
    viewer.setAnswer(textAnswer(fileText({ asOf: 1761984300000, out: [] })));
    await viewer.fireInterval();
    assert.notEqual(viewer.rendered(), 'UNTOUCHED');
    assert.equal(viewer.context.availabilityTag(viewer.payload.books[0]), 'available');
  },

  async 'an older, slower answer never overwrites a newer one'() {
    const viewer = await started({ answer: notFound });
    let resolveOlder;
    let resolveNewer;
    viewer.setAnswer(() => new Promise((resolve) => { resolveOlder = resolve; }));
    viewer.intervals[0].callback(); // check 1 starts and waits
    viewer.setAnswer(() => new Promise((resolve) => { resolveNewer = resolve; }));
    await viewer.fireVisibilityChange('visible'); // check 2 starts and waits
    resolveNewer(notFound());
    await settle();
    resolveOlder(textAnswer(fileText())());
    await settle();
    assert.deepEqual(viewer.tags(), TAGS_INLINE, 'the newest answer (404) wins');
  },

  async 'parseAvailability: the shared fixtures and the field rules'() {
    const viewer = await started({ answer: notFound });
    const parse = (bytes) => viewer.context.parseAvailability(toArrayBuffer(bytes));
    const fixture = (name) =>
      parse(fs.readFileSync(`test/fixtures/published_availability/${name}`));
    const text = (value) => parse(Buffer.from(value, 'utf8'));

    // Accepted (other_key_set parses; binding refuses it later).
    for (const name of [
      'valid.json', 'empty_out.json', 'other_key_set.json', 'asof_missing.json',
      'asof_not_a_number.json', 'asof_too_early.json', 'asof_in_future.json',
    ]) {
      assert.notEqual(fixture(name), null, `${name} must be accepted`);
    }
    // Ignored as a whole.
    for (const name of [
      'bad_key.json', 'newer_schema.json', 'no_schema_version.json', 'not_json.json',
      'malformed_key_set.json', 'missing_key_set.json', 'out_has_number.json',
      'out_not_a_list.json', 'root_is_list.json',
    ]) {
      assert.equal(fixture(name), null, `${name} must be ignored`);
    }

    const valid = fixture('valid.json');
    assert.equal(valid.keySet, KEY_SET);
    assert.equal(valid.asOf, 1761984300000);
    assert.equal(valid.out.size, 6, 'the duplicate key merges');
    assert.equal(fixture('asof_not_a_number.json').asOf, null);

    // schemaVersion: a whole number ≥ 1, and not newer than 1.
    // "1.0" is the same whole number to JSON.parse (and to the app).
    assert.notEqual(text(fileText().replace('"schemaVersion":1', '"schemaVersion":1.0')), null);
    for (const version of [0, -1, 1.5, '1', null, true]) {
      assert.equal(text(fileText({ schemaVersion: version })), null, `schemaVersion ${version}`);
    }
    assert.equal(text('null'), null, 'a null root');
    assert.equal(text('"text"'), null, 'a string root');
    assert.equal(text(fileText({ keySet: KEY_SET + ' ' })), null, 'keySet with a space');
    assert.equal(text(fileText({ out: [LISTED_KEY.toUpperCase()] })), null, 'upper-case key');
  },
};

async function main() {
  for (const [name, check] of Object.entries(checks)) {
    await check();
    console.log(`ok - ${name}`);
  }
  await settle();
  assert.deepEqual(unhandledRejections, [], 'the viewer left a rejected promise unhandled');
  console.log('viewer availability checks passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
