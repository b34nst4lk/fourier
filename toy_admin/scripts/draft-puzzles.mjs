// Drafting the 18 daily-puzzle polygons (whale and octopus are already in the
// store). Each shape is built from arcs/lines and
// ASCII-rendered so the silhouette is checked HERE, before insertion.
// Coordinates live in the authoring square's 0..100 space, y grows DOWN
// (screen space, matching the admin's canvas).
import { writeFileSync } from "node:fs";

// ---- primitives -----------------------------------------------------------
const dedupe = (pts) =>
  pts.filter(
    (p, i) =>
      i === 0 ||
      Math.abs(p[0] - pts[i - 1][0]) > 1e-9 ||
      Math.abs(p[1] - pts[i - 1][1]) > 1e-9,
  );
const line = ([x0, y0], [x1, y1], n = 1) =>
  Array.from({ length: n }, (_, i) => {
    const t = i / n;
    return [x0 + (x1 - x0) * t, y0 + (y1 - y0) * t];
  });
// circle arc, angles in degrees (0 = +x, 90 = +y which grows DOWN on screen)
const arc = (cx, cy, r, a0, a1, n = 12) =>
  Array.from({ length: n + 1 }, (_, i) => {
    const a = ((a0 + ((a1 - a0) * i) / n) * Math.PI) / 180;
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  });

// ---- the 18 drafts, in release order (easy -> hard) ------------------------
const DRAFTS = [
  {
    name: "cloud",
    dots: [
      [12, 66], [8, 56], [12, 46], [22, 42], [28, 34], [40, 30], [52, 32],
      [58, 26], [70, 26], [80, 32], [86, 42], [88, 54], [84, 64], [72, 70],
      [56, 72], [36, 72], [20, 70],
    ],
  },
  {
    name: "leaf",
    dots: [
      [52, 5], [64, 18], [71, 34], [73, 52], [66, 68], [54, 84], [50, 90],
      [44, 72], [37, 52], [40, 30], [46, 14],
    ],
  },
  {
    name: "wave",
    dots: (() => {
      const top = Array.from({ length: 17 }, (_, i) => [
        6 + (88 * i) / 16,
        42 + 11 * Math.sin((2 * Math.PI * 2 * i) / 16),
      ]);
      const bottom = Array.from({ length: 17 }, (_, i) => {
        const j = 16 - i;
        return [6 + (88 * j) / 16, 68 + 11 * Math.sin((2 * Math.PI * 2 * j) / 16)];
      });
      return [...top, [94, 68], ...bottom.slice(1), [6, 42]];
    })(),
  },
  {
    name: "heart",
    // fourier_sketch's own heart preset, ported point for point
    dots: Array.from({ length: 20 }, (_, i) => {
      const t = (2 * Math.PI * i) / 20;
      const x = 16 * Math.sin(t) ** 3;
      const y = 13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t);
      return [50 + 2.4 * x, 50 - 2.4 * y];
    }),
  },
  {
    name: "mountains",
    dots: [
      [6, 84], [24, 40], [38, 62], [56, 26], [76, 64], [90, 84], [92, 88], [4, 88],
    ],
  },
  {
    name: "island",
    dots: [
      [8, 82], [26, 52], [40, 30], [48, 44], [60, 50], [74, 68], [90, 82],
      [90, 88], [8, 88],
    ],
  },
  {
    name: "mushroom",
    dots: [
      [15, 50], [18, 32], [30, 18], [50, 12], [70, 18], [82, 32], [85, 50],
      [76, 52], [68, 52], [60, 54], [58, 62], [60, 86], [54, 90], [46, 90],
      [42, 86], [44, 62], [42, 54], [32, 52],
    ],
  },
  {
    name: "teacup",
    dots: [
      [18, 36], [80, 36], [86, 40], [92, 48], [88, 58], [79, 56], [74, 62],
      [62, 74], [46, 76], [32, 68], [24, 52],
    ],
  },
  {
    name: "lightbulb",
    dots: [
      [50, 6], [65, 11], [75, 25], [74, 41], [64, 53], [58, 58], [60, 64],
      [58, 70], [60, 78], [50, 82], [40, 78], [42, 70], [40, 64], [42, 58],
      [36, 53], [26, 41], [25, 25], [35, 11],
    ],
  },
  {
    name: "crown",
    dots: [
      [13, 72], [9, 38], [27, 53], [50, 15], [73, 53], [91, 38], [87, 72],
      [74, 79], [26, 79],
    ],
  },
  {
    name: "bell",
    dots: [
      [50, 7], [62, 13], [68, 28], [69, 46], [76, 60], [85, 71], [79, 77],
      [64, 73], [50, 71], [36, 73], [21, 77], [15, 71], [24, 60], [31, 46],
      [32, 28], [38, 13],
    ],
  },
  {
    name: "moon",
    dots: [
      [42, 7], [24, 17], [15, 38], [17, 62], [30, 82], [52, 92], [46, 74],
      [37, 55], [36, 36], [47, 17],
    ],
  },
  {
    name: "umbrella",
    dots: [
      [10, 54], [15, 38], [29, 21], [50, 11], [71, 21], [85, 38], [90, 54],
      [81, 53], [71, 51], [60, 53], [51, 51], [53, 54], [53, 78], [56, 87],
      [50, 93], [44, 87], [47, 78], [47, 54], [40, 53], [29, 51], [19, 53],
    ],
  },
  {
    name: "pine tree",
    dots: [
      [50, 4], [59, 17], [54, 19], [66, 33], [59, 35], [71, 51], [63, 53],
      [77, 71], [61, 72], [61, 88], [39, 88], [39, 72], [23, 71], [37, 53],
      [29, 51], [34, 35], [41, 33], [36, 19], [41, 17],
    ],
  },
  {
    name: "rocket",
    dots: [
      [50, 6], [59, 17], [62, 33], [64, 55], [75, 77], [70, 81], [63, 73],
      [57, 83], [50, 89], [43, 83], [37, 73], [30, 81], [25, 77], [36, 55],
      [38, 33], [41, 17],
    ],
  },
  {
    name: "sun",
    dots: (() => {
      const pts = [];
      for (let k = 0; k < 8; k++) {
        const t = -90 + 45 * k;
        for (const [a, r] of [[t - 22.5, 21], [t, 46], [t + 22.5, 21]]) {
          const rad = (a * Math.PI) / 180;
          pts.push([50 + r * Math.cos(rad), 50 + r * Math.sin(rad)]);
        }
      }
      return pts;
    })(),
  },
  {
    name: "snail",
    dots: [
      [78, 88], [87, 78], [88, 62], [80, 46], [66, 38], [50, 40], [40, 50],
      [36, 62], [26, 68], [18, 72], [6, 62], [15, 63], [17, 70], [10, 84],
      [10, 88],
    ],
  },
  {
    name: "key",
    dots: [
      [22, 26], [36, 18], [48, 26], [50, 37], [84, 36], [86, 45], [78, 45],
      [78, 54], [70, 54], [70, 45], [62, 45], [62, 52], [54, 52], [54, 45],
      [49, 45], [48, 50], [38, 57], [23, 58], [13, 47], [14, 33],
    ],
  },
];

// ---- ASCII render: 44x22 grid over the 100x100 square ----------------------
function render(dots) {
  const COLS = 44, ROWS = 22;
  const sx = (x) => Math.round((x / 100) * (COLS - 1));
  const sy = (y) => Math.round((y / 100) * (ROWS - 1));
  const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(" "));
  // plot the outline segments (inclusive both ends)
  for (let i = 0; i < dots.length; i++) {
    const [x0, y0] = dots[i];
    const [x1, y1] = dots[(i + 1) % dots.length];
    const steps = Math.max(
      Math.abs(sx(x1) - sx(x0)),
      Math.abs(sy(y1) - sy(y0)),
      1,
    );
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      const gx = Math.round(sx(x0) + (sx(x1) - sx(x0)) * t);
      const gy = Math.round(sy(y0) + (sy(y1) - sy(y0)) * t);
      grid[gy][gx] = "#";
    }
  }
  return grid.map((row) => row.join("")).join("\n");
}

const out = {};
for (const d of DRAFTS) {
  out[d.name] = d.dots;
  console.log(`\n== ${d.name} (${d.dots.length} dots) ==`);
  console.log(render(d.dots));
  // round-trip safety: every point inside the square
  for (const [x, y] of d.dots) {
    if (!(x >= 0 && x <= 100 && y >= 0 && y <= 100))
      throw new Error(`${d.name}: a point left the square`);
  }
}
writeFileSync("/tmp/drafts.json", JSON.stringify(out));
console.log("\nwritten /tmp/drafts.json with", Object.keys(out).length, "drafts");