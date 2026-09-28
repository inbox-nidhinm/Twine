// Runs code.js against a stand-in for Figma's plugin interface, on a
// made-up selection with one of everything the plugin handles, and writes
// the copy it makes to sample-payload.json, which Twine's tests read
// (MotionImportTests, FigmaPluginSampleTests). Run it after changing
// code.js:
//
//     node FigmaPlugin/test/run.js
//
// It checks what can be checked without Figma: that every kind of layer is
// described, flattened or skipped as meant, and that the copy is valid.

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const MIXED = Symbol("mixed");
// A 2 by 1 PNG, standing in for everything Figma would draw or store.
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGP4z8DwHwQZ/gMAG/0D/eqA0WQAAAAASUVORK5CYII=", "base64");

function translate(x, y) { return [[1, 0, x], [0, 1, y]]; }

function node(type, props) {
  const n = Object.assign({
    type: type, name: type, visible: true, locked: false, opacity: 1, blendMode: "PASS_THROUGH",
    absoluteTransform: translate(0, 0), width: 10, height: 10, effects: [], fills: [], strokes: [],
    strokeWeight: 1, strokeAlign: "INSIDE", dashPattern: [], strokeCap: "NONE", strokeJoin: "MITER",
    isMask: false, parent: null,
    exportAsync: async function (settings) {
      if (settings.format === "SVG_STRING") {
        return '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><path d="M0 0H10V10Z" fill="red"/></svg>';
      }
      return new Uint8Array(PNG);
    },
  }, props);
  n.absoluteRenderBounds = props.absoluteRenderBounds || {
    x: n.absoluteTransform[0][2], y: n.absoluteTransform[1][2], width: n.width, height: n.height,
  };
  n.absoluteBoundingBox = n.absoluteRenderBounds;
  if (n.children) for (const child of n.children) child.parent = n;
  return n;
}

const solid = function (r, g, b, opacity) {
  return { type: "SOLID", visible: true, opacity: opacity === undefined ? 1 : opacity, color: { r: r, g: g, b: b }, blendMode: "NORMAL" };
};

function textNode(props, segments) {
  return node("TEXT", Object.assign({
    characters: "Hello", fontName: { family: "Inter", style: "Semi Bold" }, fontSize: 24,
    letterSpacing: { unit: "PERCENT", value: -2 }, lineHeight: { unit: "PIXELS", value: 32 },
    textAlignHorizontal: "CENTER", textAlignVertical: "TOP", textAutoResize: "WIDTH_AND_HEIGHT", textDecoration: "NONE",
    textCase: "ORIGINAL", paragraphSpacing: 0, paragraphIndent: 0, textTruncation: "DISABLED",
    fills: [solid(0.1, 0.1, 0.1)], strokes: [],
    getStyledTextSegments: function () { return segments || [{ listOptions: { type: "NONE" } }]; },
  }, props));
}

const card = node("FRAME", {
  name: "Card", absoluteTransform: translate(100, 50), width: 320, height: 200, clipsContent: true,
  topLeftRadius: 16, topRightRadius: 16, bottomRightRadius: 16, bottomLeftRadius: 16, cornerRadius: 16,
  fills: [solid(1, 1, 1), { type: "GRADIENT_ANGULAR", visible: true, gradientStops: [], gradientTransform: translate(0, 0) }],
  strokes: [solid(0, 0, 0, 0.1)],
  effects: [
    { type: "DROP_SHADOW", visible: true, color: { r: 0, g: 0, b: 0, a: 0.2 }, offset: { x: 0, y: 8 }, radius: 24, spread: 0 },
    { type: "NOISE", visible: true },
  ],
  children: [
    node("RECTANGLE", {
      name: "Photo", absoluteTransform: translate(116, 66), width: 120, height: 80, cornerSmoothing: 0,
      topLeftRadius: 8, topRightRadius: 8, bottomRightRadius: 8, bottomLeftRadius: 8,
      fills: [{ type: "IMAGE", visible: true, opacity: 1, imageHash: "photo-hash", scaleMode: "FILL", rotation: 0, filters: {} }],
    }),
    textNode({ name: "Title", absoluteTransform: translate(250, 70), width: 80, height: 32 }),
    textNode({ name: "Mixed", absoluteTransform: translate(250, 110), width: 80, height: 32 }, [{}, {}]),
    textNode({ name: "Leaning", absoluteTransform: translate(250, 150), width: 80, height: 32, fontName: { family: "Inter", style: "Italic" } }),
    // Slanted by Figma's transform: Twine holds skew, so these stay a shape and text.
    node("RECTANGLE", { name: "Slanted", absoluteTransform: [[1, 0.4, 300], [0, 1, 60]], width: 40, height: 20,
      topLeftRadius: 0, topRightRadius: 0, bottomRightRadius: 0, bottomLeftRadius: 0, cornerSmoothing: 0, fills: [solid(1, 0, 0)] }),
    textNode({ name: "Sheared", absoluteTransform: [[1, 0.3, 300], [0, 1, 100]], width: 80, height: 32 }),
    node("VECTOR", {
      name: "Icon", absoluteTransform: translate(130, 160), width: 24, height: 24, fills: [solid(0.3, 0.6, 0.9)],
      vectorPaths: [{ windingRule: "EVENODD", data: "M0 0 L24 0 L24 24 L0 24 Z M6 6 L18 6 L18 18 L6 18 Z" }],
      vectorNetwork: { regions: [] },
    }),
    node("VECTOR", {
      name: "Painted Regions", absoluteTransform: translate(160, 160), width: 24, height: 24,
      vectorPaths: [{ windingRule: "NONZERO", data: "M0 0 L24 0 L24 24 Z" }],
      vectorNetwork: { regions: [{ fills: [solid(1, 0, 0)] }] },
    }),
    node("GROUP", {
      name: "Masked", absoluteTransform: translate(200, 160), width: 30, height: 30,
      children: [
        node("ELLIPSE", { name: "Mask", isMask: true, maskType: "ALPHA", absoluteTransform: translate(200, 160), width: 30, height: 30,
          arcData: { startingAngle: 0, endingAngle: 2 * Math.PI, innerRadius: 0 }, fills: [solid(0, 0, 0)] }),
        node("STAR", { name: "Star", absoluteTransform: translate(200, 160), width: 30, height: 30, pointCount: 5, innerRadius: 0.4,
          cornerRadius: 2, fills: [solid(1, 0.8, 0)] }),
      ],
    }),
    node("LINE", { name: "Rule", absoluteTransform: translate(116, 190), width: 288, height: 0, strokes: [solid(0, 0, 0)], strokeWeight: 2, strokeCap: "ROUND" }),
    node("STICKY", { name: "Note", absoluteTransform: translate(300, 180), width: 20, height: 20 }),
    // A background of pictures stacked on a colour: only the top one is kept.
    node("FRAME", { name: "Stacked", absoluteTransform: translate(340, 200), width: 60, height: 40, clipsContent: true,
      topLeftRadius: 6, topRightRadius: 6, bottomRightRadius: 6, bottomLeftRadius: 6, cornerRadius: 6, children: [],
      fills: [solid(0, 0, 0),
        { type: "IMAGE", visible: true, opacity: 1, imageHash: "under-1", scaleMode: "FILL", rotation: 0, filters: {} },
        { type: "IMAGE", visible: true, opacity: 1, imageHash: "under-2", scaleMode: "FILL", rotation: 0, filters: { exposure: 0.5 } },
        { type: "IMAGE", visible: true, opacity: 1, imageHash: "top", scaleMode: "FILL", rotation: 0, filters: {} }] }),
    node("SLICE", { name: "Export Area", absoluteTransform: translate(100, 50), width: 320, height: 200 }),
  ],
});

// The stand-in for Figma.
const messages = [];
const figma = {
  mixed: MIXED,
  currentPage: { selection: [card] },
  showUI: function () {},
  on: function () {},
  ui: { postMessage: function (m) { messages.push(m); }, onmessage: null },
  getImageByHash: function () { return { getBytesAsync: async function () { return new Uint8Array(PNG); } }; },
  base64Encode: function (bytes) { return Buffer.from(bytes).toString("base64"); },
};
const pageNode = { type: "PAGE", children: [card], parent: null };
card.parent = pageNode;

const code = fs.readFileSync(path.join(__dirname, "..", "code.js"), "utf8");
vm.runInNewContext(code, { figma: figma, __html__: "", console: console, Math: Math, Map: Map, Object: Object, JSON: JSON, String: String, Symbol: Symbol });

(async function () {
  // Objects from inside the sandbox are compared as text, their prototypes
  // being the sandbox's own.
  const selection = messages[0];
  assert.strictEqual(selection.type, "selection");
  assert.strictEqual(selection.count, 1);
  assert.strictEqual(selection.name, "Card");
  assert.strictEqual(selection.width, 320);
  assert.strictEqual(selection.height, 200);
  assert(selection.layers > 10, "every layer inside is counted");
  // The panel's picture of the selection follows.
  await new Promise(function (done) { setTimeout(done, 0); });
  const preview = messages.find(function (m) { return m.type === "preview"; });
  assert(preview && preview.parts.length === 1 && Math.abs(preview.aspect - 1.6) < 1e-9, "the card is drawn for the panel");
  await figma.ui.onmessage({ type: "copy" });
  const done = messages.find(function (m) { return m.type === "payload"; });
  assert(done, "no copy: " + JSON.stringify(messages.filter(function (m) { return m.type === "error"; })));
  const payload = JSON.parse(done.text);
  assert.strictEqual(payload.format, "twine.figma");
  const frame = payload.nodes[0];
  const kinds = frame.children.map(function (c) { return c.name + ":" + c.kind; });
  assert.deepStrictEqual(kinds, ["Photo:rectangle", "Title:text", "Mixed:picture", "Leaning:picture", "Slanted:rectangle", "Sheared:text", "Icon:vector",
    "Painted Regions:svg", "Masked:group", "Rule:line", "Note:picture", "Stacked:frame"]);
  assert.deepStrictEqual(frame.fills.map(function (f) { return f.type; }).join(), "SOLID", "the angular gradient is left out");
  assert.deepStrictEqual(frame.effects.map(function (e) { return e.type; }).join(), "DROP_SHADOW", "noise is left out");
  assert(payload.warnings.some(function (w) { return w.indexOf("Card") === 0; }), "the left-out gradient is said");
  assert.ok(payload.images["photo-hash"], "the photo travels with the copy");
  const stacked = frame.children[frame.children.length - 1];
  assert.deepStrictEqual(stacked.fills.map(function (f) { return f.image || f.type; }), ["SOLID", "top"], "only the top picture is kept");
  assert(!payload.images["under-1"] && !payload.images["under-2"] && payload.images["top"], "and only it is copied");
  assert.strictEqual(frame.children[1].text.letterSpacing, -0.48);
  assert.strictEqual(frame.children[8].children[0].isMask, true);
  assert.deepStrictEqual(frame.children[4].transform, [1, 0, 0.4, 1, 300, 60], "the slant travels in the transform");
  const percents = messages.filter(function (m) { return m.type === "progress"; }).map(function (m) { return m.percent; });
  assert(percents.length > 1 && percents.every(function (p, i) { return i === 0 || p > percents[i - 1]; }), "progress only rises");
  fs.writeFileSync(path.join(__dirname, "sample-payload.json"), JSON.stringify(payload, null, 1));
  console.log("ok: " + kinds.length + " layers, " + percents.length + " progress steps, wrote sample-payload.json");
})().catch(function (error) {
  console.error(error);
  process.exit(1);
});
