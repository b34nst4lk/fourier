export function cos(x) {
  return Math.cos(x);
}

export function sin(x) {
  return Math.sin(x);
}

export function atan2(y, x) {
  return Math.atan2(y, x);
}

export function sqrt(x) {
  return Math.sqrt(x);
}

export function store_get(key, otherwise) {
  try {
    const value = window.localStorage.getItem(key);
    return value === null ? otherwise : value;
  } catch {
    return otherwise;
  }
}

export function store_set(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // private browsing / quota errors: autosave is best-effort
  }
}

// Convert a pointer event's client coords into sketch-space (0..100).
// The SVG viewBox is 100x100 letterboxed in its element (default
// preserveAspectRatio), so the conversion accounts for letterbox offsets.
// The element is looked up by id — decoders may receive sanitized events,
// so we never trust event.currentTarget.
export function event_point(event, svg_id, otherwise) {
  try {
    const svg = document.getElementById(svg_id);
    const rect = svg.getBoundingClientRect();
    const scale = Math.min(rect.width, rect.height) / 100;
    const ox = (rect.width - scale * 100) / 2;
    const oy = (rect.height - scale * 100) / 2;
    const x = (event.clientX - rect.left - ox) / scale;
    const y = (event.clientY - rect.top - oy) / scale;
    return [x, y];
  } catch {
    return otherwise;
  }
}
export function now_ms() {
  return performance.now();
}
