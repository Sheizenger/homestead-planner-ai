import type { Plot } from '../../domain/types';
import { CATEGORY_STYLES } from '../../domain/categories';
import { polygonBounds } from '../../engine/geometry';
import { computeWaterfrontZone } from '../../engine/waterfront';
import { t, type Locale } from '../../i18n/translations';

// A chain of alternating quadratic bumps — a simple, cheap way to draw a
// long wavy "water" line without needing a real wave-simulation curve.
function wavyPath(x0: number, x1: number, y: number, amp: number, bumps: number): string {
  const step = (x1 - x0) / (bumps * 2);
  let d = `M ${x0} ${y}`;
  let cx = x0;
  for (let i = 0; i < bumps * 2; i++) {
    const ex = cx + step;
    d += ` Q ${cx + step / 2} ${y + (i % 2 === 0 ? -amp : amp)}, ${ex} ${y}`;
    cx = ex;
  }
  return d;
}

// Renders the plot's river/lake/pond frontage — a property of the plot
// itself (shared by every variant), not a generated object, so it's drawn
// directly from project.plot rather than per-variant data.
export function WaterfrontZone({ plot, themeKey, locale }: { plot: Plot; themeKey: 'light' | 'dark'; locale: Locale }) {
  const zone = computeWaterfrontZone(plot);
  if (!zone || !plot.waterfront) return null;

  const bounds = polygonBounds(zone.boundary);
  const w = bounds.maxX - bounds.minX;
  const h = bounds.maxY - bounds.minY;
  const cx = (bounds.minX + bounds.maxX) / 2;
  const cy = (bounds.minY + bounds.maxY) / 2;
  const horizontal = w >= h;
  const longLen = horizontal ? w : h;
  const shortLen = horizontal ? h : w;
  const fill = CATEGORY_STYLES.water[themeKey].fill;
  const stroke = CATEGORY_STYLES.water[themeKey].stroke;
  const margin = Math.min(1, shortLen * 0.15);
  const amp = Math.min(0.35, shortLen / 8);
  const spacing = 2.2;
  const rows = Math.max(1, Math.floor((shortLen - margin * 2) / spacing) + 1);
  const bumps = Math.max(2, Math.round(longLen / 4));

  const waveLines = Array.from({ length: rows }, (_, i) => {
    const y = rows === 1 ? 0 : -shortLen / 2 + margin + (i * (shortLen - margin * 2)) / (rows - 1);
    return (
      <path
        key={i}
        d={wavyPath(-longLen / 2 + margin, longLen / 2 - margin, y, amp, bumps)}
        fill="none"
        stroke={stroke}
        strokeWidth={0.08}
        opacity={0.5}
      />
    );
  });

  const fontSize = Math.max(0.6, Math.min(1.4, shortLen / 3));

  return (
    <g>
      <polygon
        points={zone.boundary.map((p) => `${p.x},${p.y}`).join(' ')}
        fill={fill}
        fillOpacity={0.55}
        stroke={stroke}
        strokeWidth={0.15}
      />
      <g transform={`translate(${cx} ${cy}) ${horizontal ? '' : 'rotate(90)'}`}>{waveLines}</g>
      <text
        x={cx}
        y={cy}
        textAnchor="middle"
        dominantBaseline="middle"
        fontSize={fontSize}
        fill={stroke}
        opacity={0.75}
        className="pointer-events-none select-none"
      >
        {t(locale, `waterfront.${plot.waterfront.type}`)}
      </text>
    </g>
  );
}
