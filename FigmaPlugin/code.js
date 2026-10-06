// Twine for Figma: copies the selected layers so Twine can paste them.
//
// Each layer is described as Twine builds it (frames, groups, shapes,
// vectors, text), with its absolute transform, so Twine can place it in
// whatever holds it. What Twine cannot hold is flattened here, while Figma
// can still draw it: as a picture Figma renders (mixed text styles, italics,
// diamond gradients, picture filters and the like), or as Figma's own SVG
// (vectors whose regions are painted differently). Skewed layers travel as
// they are: Twine holds skew. Picture
// fills travel with the copy, once each. The whole copy is one line of JSON
// on the clipboard, which Twine recognises by its `format`.
//
// Written for Figma's plugin sandbox, without a build step: plain modern
// JavaScript, no optional chaining.

const FORMAT = "twine.figma";
const VERSION = 1;
// Pictures Figma draws, at twice their size, so they stay sharp.
const PICTURE_SCALE = 2;

figma.showUI(__html__, { width: 339, height: 380, themeColors: false });

// The panel's preview: at most this many layers drawn, each at most this
// many pixels on its longer side (twice the size shown, so it stays sharp).
const PREVIEW_LAYERS = 12;
const PREVIEW_PIXELS = 480;

/// What the panel shows of the selection: its name, its size (the box
/// around all of it) and how many layers it holds.
function selectionInfo() {
  const selection = figma.currentPage.selection;
  if (selection.length === 0) return { type: "selection", count: 0, name: "" };
  const box = bounds(selection);
  return {
    type: "selection",
    count: selection.length,
    name: selection.length === 1 ? selection[0].name : selection.length + " layers",
    width: Math.round(box.width),
    height: Math.round(box.height),
    layers: selection.reduce(function (sum, node) { return sum + count(node); }, 0),
  };
}

function bounds(nodes) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const node of nodes) {
    const b = node.absoluteBoundingBox;
    if (!b) continue;
    minX = Math.min(minX, b.x); minY = Math.min(minY, b.y);
    maxX = Math.max(maxX, b.x + b.width); maxY = Math.max(maxY, b.y + b.height);
  }
  if (minX === Infinity) return { x: 0, y: 0, width: 0, height: 0 };
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

/// A picture of the selection for the panel: each layer drawn by Figma,
/// with where it sits in the box around them all, back to front, so the
/// panel lays them out as the canvas does. A newer selection wins: a
/// picture still being drawn for an older one is dropped.
let previewToken = 0;
async function sendPreview() {
  const token = ++previewToken;
  const selection = sortedBack(figma.currentPage.selection.slice()).slice(-PREVIEW_LAYERS);
  if (selection.length === 0) return;
  const box = bounds(selection);
  const longest = Math.max(box.width, box.height, 1);
  const scale = Math.min(PREVIEW_PIXELS / longest, 2);
  const parts = [];
  for (const node of selection) {
    const b = node.absoluteBoundingBox;
    if (!b || b.width <= 0 || b.height <= 0) continue;
    try {
      const bytes = await node.exportAsync({ format: "PNG", constraint: { type: "SCALE", value: scale } });
      if (token !== previewToken) return;
      parts.push({ png: figma.base64Encode(bytes), x: (b.x - box.x) / longest, y: (b.y - box.y) / longest,
                   width: b.width / longest, height: b.height / longest });
    } catch (error) {
      // A layer Figma cannot draw is left out of the picture.
    }
  }
  if (token !== previewToken) return;
  figma.ui.postMessage({ type: "preview", aspect: box.width / Math.max(box.height, 1), parts: parts });
}

function selectionChanged() {
  figma.ui.postMessage(selectionInfo());
  sendPreview();
}

figma.on("selectionchange", selectionChanged);
selectionChanged();

figma.ui.onmessage = async function (message) {
  if (message.type !== "copy") return;
  const selection = figma.currentPage.selection.slice();
  if (selection.length === 0) return;
  try {
    const payload = await copy(selection);
    figma.ui.postMessage({ type: "payload", text: JSON.stringify(payload), warnings: payload.warnings });
  } catch (error) {
    figma.ui.postMessage({ type: "error", message: String(error && error.message ? error.message : error) });
  }
};

// MARK: The copy

async function copy(selection) {
  const context = {
    done: 0,
    total: 1,
    lastReported: -1,
    images: {},
    warnings: [],
  };
  context.total = selection.reduce(function (sum, node) { return sum + count(node); }, 0);
  // Back to front, as Figma's layers panel lists them from the bottom.
  const ordered = sortedBack(selection);
  const nodes = [];
  for (const node of ordered) {
    const made = await describe(node, context);
    if (made) nodes.push(made);
  }
  const hashes = Object.keys(context.images);
  context.total += hashes.length;
  for (const hash of hashes) {
    const image = figma.getImageByHash(hash);
    if (image) {
      const bytes = await image.getBytesAsync();
      context.images[hash] = figma.base64Encode(bytes);
    } else {
      delete context.images[hash];
    }
    step(context);
  }
  return { format: FORMAT, version: VERSION, nodes: nodes, images: context.images, warnings: context.warnings };
}

/// Layers and everything inside them, for the progress count.
function count(node) {
  let n = 1;
  if ("children" in node && !isFlattened(node)) for (const child of node.children) n += count(child);
  return n;
}

function step(context) {
  context.done += 1;
  const percent = Math.min(99, Math.floor((context.done / Math.max(context.total, 1)) * 100));
  // Pictures join the count once the layers are read, which can pull the
  // share back a little; the panel only ever counts up.
  if (percent > context.lastReported) {
    context.lastReported = percent;
    figma.ui.postMessage({ type: "progress", percent: percent });
  }
}

/// A selection in the order its layers are stacked: siblings by their
/// place in their parent, others by where they come in the page.
function sortedBack(nodes) {
  function path(node) {
    const out = [];
    let current = node;
    while (current && current.parent) {
      out.unshift(current.parent.children.indexOf(current));
      current = current.parent;
    }
    return out;
  }
  const paths = new Map(nodes.map(function (n) { return [n, path(n)]; }));
  return nodes.slice().sort(function (a, b) {
    const pa = paths.get(a), pb = paths.get(b);
    for (let i = 0; i < Math.min(pa.length, pb.length); i++) if (pa[i] !== pb[i]) return pa[i] - pb[i];
    return pa.length - pb.length;
  });
}

// MARK: One layer

async function describe(node, context) {
  step(context);
  const base = {
    name: node.name,
    visible: node.visible,
    locked: node.locked,
    opacity: "opacity" in node ? node.opacity : 1,
    blend: "blendMode" in node ? node.blendMode : "NORMAL",
    transform: flat(node.absoluteTransform),
    width: node.width,
    height: node.height,
  };
  if ("isMask" in node && node.isMask) {
    base.isMask = true;
    base.maskType = node.maskType || "ALPHA";
  }

  const flattening = flattenAs(node);
  if (flattening === "skip") return null;
  if (flattening === "picture") return await picture(node, base, context);
  if (flattening === "svg") return await svg(node, base, context);

  switch (node.type) {
    case "FRAME":
    case "COMPONENT":
    case "COMPONENT_SET":
    case "INSTANCE":
    case "SECTION":
      return await container(node, base, "frame", context);
    case "GROUP":
      return await container(node, base, "group", context);
    case "RECTANGLE":
      return Object.assign(base, { kind: "rectangle", radii: radii(node) }, look(node, context));
    case "ELLIPSE":
      return Object.assign(base, {
        kind: "ellipse",
        arc: { start: node.arcData.startingAngle, end: node.arcData.endingAngle, inner: node.arcData.innerRadius },
      }, look(node, context));
    case "POLYGON":
      return Object.assign(base, { kind: "polygon", count: node.pointCount, radii: [number(node.cornerRadius)] }, look(node, context));
    case "STAR":
      return Object.assign(base, {
        kind: "star", count: node.pointCount, inner: node.innerRadius, radii: [number(node.cornerRadius)],
      }, look(node, context));
    case "LINE":
      return Object.assign(base, { kind: "line" }, look(node, context));
    case "VECTOR":
      return Object.assign(base, {
        kind: "vector",
        paths: node.vectorPaths.map(function (p) { return { rule: p.windingRule, d: p.data }; }),
        corners: vectorCorners(node),
      }, look(node, context));
    case "BOOLEAN_OPERATION":
      return Object.assign(base, {
        kind: "vector",
        paths: node.fillGeometry.map(function (p) { return { rule: p.windingRule, d: p.data }; }),
      }, look(node, context));
    case "TEXT":
      return Object.assign(base, { kind: "text", text: text(node), fills: paints(node.fills, context) }, effectsOf(node));
    default:
      return await picture(node, base, context);
  }
}

async function container(node, base, kind, context) {
  const children = [];
  for (const child of node.children) {
    const made = await describe(child, context);
    if (made) children.push(made);
  }
  const out = Object.assign(base, { kind: kind, children: children }, effectsOf(node));
  if (kind === "frame") {
    Object.assign(out, look(node, context), { radii: radii(node), clips: node.type === "SECTION" ? false : !!node.clipsContent });
    // A frame is not flattened, or what it holds would be too; a paint
    // Twine lacks is left out instead, and said so.
    const lacking = (node.fills === figma.mixed ? [] : node.fills).concat(node.strokes).filter(function (p) {
      return p.visible !== false && DRAWN_PAINTS.indexOf(p.type) < 0;
    });
    if (lacking.length) {
      const drawn = function (p) { return DRAWN_PAINTS.indexOf(p.type) >= 0; };
      if (out.fills) out.fills = out.fills.filter(drawn);
      if (out.strokes) out.strokes = out.strokes.filter(drawn);
      context.warnings.push(node.name + " is painted with a gradient Twine lacks, which was left out.");
    }
    if (hasUnevenBorder(node)) {
      delete out.strokes;
      context.warnings.push(node.name + " has a different border on each side, which was left out.");
    }
  }
  return out;
}

// MARK: What Twine cannot hold

/// The paints Twine draws as they are: everything else (diamond gradients,
/// video) makes a layer a picture, or is left out of a frame.
const DRAWN_PAINTS = ["SOLID", "GRADIENT_LINEAR", "GRADIENT_RADIAL", "GRADIENT_ANGULAR", "IMAGE"];

/// "picture" for what Figma must draw, "svg" for vectors Figma writes out,
/// "skip" for what draws nothing, or nothing for a layer Twine can build.
function flattenAs(node) {
  if (node.type === "SLICE") return "skip";
  const known = ["FRAME", "COMPONENT", "COMPONENT_SET", "INSTANCE", "SECTION", "GROUP", "RECTANGLE", "ELLIPSE",
    "POLYGON", "STAR", "LINE", "VECTOR", "BOOLEAN_OPERATION", "TEXT"];
  if (known.indexOf(node.type) < 0) return "picture";
  const isContainer = ["FRAME", "COMPONENT", "COMPONENT_SET", "INSTANCE", "SECTION", "GROUP"].indexOf(node.type) >= 0;
  // A luminance mask inside: the whole of it, as drawn.
  if (isContainer && node.children.some(function (c) { return c.isMask && c.maskType === "LUMINANCE"; })) return "picture";
  if (node.type === "TEXT") return textFits(node) ? null : "picture";
  if (!isContainer && paintsNeedPicture(node)) return "picture";
  if (node.type === "VECTOR") {
    const rules = node.vectorPaths.map(function (p) { return p.windingRule; }).filter(function (r) { return r !== "NONE"; });
    if (rules.some(function (r) { return r !== rules[0]; })) return "svg";
    const regions = node.vectorNetwork && node.vectorNetwork.regions;
    if (regions && regions.some(function (r) { return r.fills && r.fills.length; })) return "svg";
  }
  if (node.type === "RECTANGLE" && node.cornerSmoothing > 0) return "svg";
  return null;
}

function isFlattened(node) {
  const as = flattenAs(node);
  return as === "picture" || as === "svg";
}

/// Paints Twine draws: solid colours, linear, radial and angular gradients, and
/// pictures without filters, turned in quarters, blended normally.
function paintsNeedPicture(node) {
  const lists = [];
  if ("fills" in node && node.fills !== figma.mixed) lists.push(keptPaints(node.fills));
  if ("strokes" in node) lists.push(node.strokes);
  for (const list of lists) {
    for (const p of list) {
      if (p.visible === false) continue;
      if (DRAWN_PAINTS.indexOf(p.type) < 0) return true;
      if (p.blendMode && p.blendMode !== "NORMAL" && p.blendMode !== "PASS_THROUGH") return true;
      if (p.type === "IMAGE") {
        const f = p.filters || {};
        if (["exposure", "contrast", "saturation", "temperature", "tint", "highlights", "shadows"].some(function (k) { return f[k]; })) return true;
        if ((p.rotation || 0) % 90 !== 0) return true;
        if (p.scaleMode === "CROP" && p.imageTransform && (Math.abs(p.imageTransform[0][1]) > 1e-6 || Math.abs(p.imageTransform[1][0]) > 1e-6)) return true;
      }
    }
  }
  if ("strokes" in node && node.strokes.some(function (p) { return p.visible !== false && p.type === "IMAGE"; })) return true;
  if (hasUnevenBorder(node)) return true;
  return false;
}

function hasUnevenBorder(node) {
  if (!("strokeTopWeight" in node) || node.strokeWeight !== figma.mixed) return false;
  return true;
}

/// Text Twine can set: one style throughout, upright, undecorated, one
/// solid colour, no stroke, laid out from the top.
function textFits(node) {
  if (node.fontName === figma.mixed || node.fontSize === figma.mixed || node.fills === figma.mixed) return false;
  if (node.letterSpacing === figma.mixed || node.lineHeight === figma.mixed) return false;
  if (node.textDecoration !== "NONE" || node.textCase !== "ORIGINAL") return false;
  if (/italic|oblique/i.test(node.fontName.style)) return false;
  if (node.paragraphSpacing || node.paragraphIndent) return false;
  if (node.textAutoResize === "TRUNCATE" || node.textTruncation === "ENDING") return false;
  if (node.textAutoResize === "NONE" && node.textAlignVertical !== "TOP") return false;
  const fills = node.fills.filter(function (p) { return p.visible !== false; });
  if (fills.length > 1 || (fills.length === 1 && fills[0].type !== "SOLID")) return false;
  if (node.strokes.some(function (p) { return p.visible !== false; })) return false;
  if (node.getStyledTextSegments) {
    const segments = node.getStyledTextSegments(["fontName", "fontSize", "fills", "letterSpacing", "lineHeight",
      "textDecoration", "textCase", "listOptions"]);
    if (segments.length > 1) return false;
    if (segments.some(function (s) { return s.listOptions && s.listOptions.type !== "NONE"; })) return false;
  }
  return true;
}

async function picture(node, base, context) {
  // A hidden layer draws nothing to flatten.
  if (!node.visible) return null;
  const bounds = node.absoluteRenderBounds || node.absoluteBoundingBox;
  if (!bounds || bounds.width <= 0 || bounds.height <= 0) return null;
  let bytes;
  try {
    bytes = await node.exportAsync({ format: "PNG", constraint: { type: "SCALE", value: PICTURE_SCALE } });
  } catch (error) {
    context.warnings.push(node.name + " could not be drawn, and was left out.");
    return null;
  }
  return {
    kind: "picture", name: base.name, visible: base.visible, locked: base.locked,
    isMask: base.isMask, maskType: base.maskType,
    transform: base.transform, width: base.width, height: base.height,
    png: figma.base64Encode(bytes), bounds: [bounds.x, bounds.y, bounds.width, bounds.height],
  };
}

async function svg(node, base, context) {
  const bounds = node.absoluteRenderBounds || node.absoluteBoundingBox;
  if (!bounds) return null;
  let text;
  try {
    text = await node.exportAsync({ format: "SVG_STRING", svgIdAttribute: true, svgOutlineText: true });
  } catch (error) {
    return await picture(node, base, context);
  }
  return Object.assign(base, { kind: "svg", svg: text, bounds: [bounds.x, bounds.y, bounds.width, bounds.height] });
}

// MARK: Parts

function flat(t) {
  return [t[0][0], t[1][0], t[0][1], t[1][1], t[0][2], t[1][2]];
}

function number(v) {
  return typeof v === "number" ? v : 0;
}

/// A vector's rounded points as [x, y, radius] in its own space: Figma keeps
/// the radius on the network's vertices (or one for the whole vector), not
/// in `vectorPaths`, which are drawn sharp. Twine matches them by place.
function vectorCorners(node) {
  const vertices = node.vectorNetwork && node.vectorNetwork.vertices;
  if (!vertices) return undefined;
  const all = number(node.cornerRadius);
  const corners = [];
  for (const v of vertices) {
    const r = typeof v.cornerRadius === "number" ? v.cornerRadius : all;
    if (r > 0) corners.push([v.x, v.y, r]);
  }
  return corners.length ? corners : undefined;
}

function radii(node) {
  if ("topLeftRadius" in node) {
    return [node.topLeftRadius, node.topRightRadius, node.bottomRightRadius, node.bottomLeftRadius];
  }
  return [number(node.cornerRadius)];
}

function look(node, context) {
  const out = effectsOf(node);
  if ("fills" in node && node.fills !== figma.mixed) out.fills = paints(node.fills, context);
  if ("strokes" in node && node.strokes.length) {
    out.strokes = paints(node.strokes, context);
    out.strokeWeight = node.strokeWeight === figma.mixed ? 0 : node.strokeWeight;
    out.strokeAlign = node.strokeAlign;
    out.dash = node.dashPattern && node.dashPattern.length ? node.dashPattern.slice() : undefined;
    out.cap = node.strokeCap === figma.mixed ? "NONE" : node.strokeCap;
    out.join = node.strokeJoin === figma.mixed ? "MITER" : node.strokeJoin;
  }
  return out;
}

/// A layer's fills with only one picture among them: the topmost shown, or
/// the topmost when none is shown. Pictures stacked under it cannot be seen
/// through it, so they are not copied (the user's choice).
function keptPaints(list) {
  if (!list || list === figma.mixed) return list;
  let top = -1;
  for (let i = list.length - 1; i >= 0; i--) {
    if (list[i].type === "IMAGE" && list[i].visible !== false) { top = i; break; }
  }
  if (top < 0) for (let i = list.length - 1; i >= 0; i--) { if (list[i].type === "IMAGE") { top = i; break; } }
  return list.filter(function (p, i) { return p.type !== "IMAGE" || i === top; });
}

function paints(list, context) {
  if (!list || list === figma.mixed) return [];
  return keptPaints(list).map(function (p) {
    const out = { type: p.type, visible: p.visible !== false, opacity: p.opacity === undefined ? 1 : p.opacity };
    if (p.type === "SOLID") out.color = { r: p.color.r, g: p.color.g, b: p.color.b, a: 1 };
    if (p.type === "GRADIENT_LINEAR" || p.type === "GRADIENT_RADIAL" || p.type === "GRADIENT_ANGULAR") {
      out.stops = p.gradientStops.map(function (s) {
        return { position: s.position, color: { r: s.color.r, g: s.color.g, b: s.color.b, a: s.color.a } };
      });
      out.transform = flat(p.gradientTransform);
    }
    if (p.type === "IMAGE" && p.imageHash) {
      context.images[p.imageHash] = true;
      out.image = p.imageHash;
      out.scaleMode = p.scaleMode;
      if (p.imageTransform) out.imageTransform = flat(p.imageTransform);
      if (p.scalingFactor !== undefined) out.scalingFactor = p.scalingFactor;
      if (p.rotation !== undefined) out.rotation = p.rotation;
    }
    return out;
  });
}

function effectsOf(node) {
  if (!("effects" in node)) return {};
  const effects = node.effects.filter(function (e) {
    return ["DROP_SHADOW", "INNER_SHADOW", "LAYER_BLUR", "BACKGROUND_BLUR"].indexOf(e.type) >= 0;
  }).map(function (e) {
    const out = { type: e.type, visible: e.visible !== false, radius: e.radius };
    if (e.color) out.color = { r: e.color.r, g: e.color.g, b: e.color.b, a: e.color.a };
    if (e.offset) out.offset = { x: e.offset.x, y: e.offset.y };
    if (e.spread !== undefined) out.spread = e.spread;
    return out;
  });
  return effects.length ? { effects: effects } : {};
}

function text(node) {
  const size = node.fontSize;
  const spacing = node.letterSpacing;
  const height = node.lineHeight;
  return {
    characters: node.characters,
    family: node.fontName.family,
    style: node.fontName.style,
    size: size,
    letterSpacing: spacing.unit === "PERCENT" ? spacing.value / 100 * size : spacing.value,
    lineHeight: height.unit === "AUTO" ? undefined : height.unit === "PERCENT" ? height.value / 100 * size : height.value,
    align: node.textAlignHorizontal,
    autoResize: node.textAutoResize,
  };
}
