import type { Plot } from '../../domain/types';
import { computeContourLines } from '../../engine/elevation';

// Thin dashed contour lines across the plot for a configured linear grade —
// a coarse but immediately legible stand-in for a real survey contour map,
// labeled with elevation so it's clear which direction is uphill.
export function ContourLines({ plot, themeKey }: { plot: Plot; themeKey: 'light' | 'dark' }) {
  if (!plot.elevation) return null;
  const lines = computeContourLines(plot);
  if (lines.length === 0) return null;
  const stroke = themeKey === 'dark' ? '#78716c' : '#a8a29e';

  return (
    <g className="pointer-events-none select-none">
      {lines.map((line) => {
        const midX = (line.a.x + line.b.x) / 2;
        const midY = (line.a.y + line.b.y) / 2;
        return (
          <g key={line.elevationM}>
            <line x1={line.a.x} y1={line.a.y} x2={line.b.x} y2={line.b.y} stroke={stroke} strokeWidth={0.06} strokeDasharray="0.8,0.6" opacity={0.6} />
            <text x={midX + 0.3} y={midY - 0.3} fontSize={0.7} fill={stroke} opacity={0.85}>
              +{line.elevationM.toFixed(line.elevationM % 1 === 0 ? 0 : 1)} m
            </text>
          </g>
        );
      })}
    </g>
  );
}
