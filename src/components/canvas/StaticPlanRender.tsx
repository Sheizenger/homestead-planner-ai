import { forwardRef } from 'react';
import type { LayoutVariant, Plot, Season } from '../../domain/types';
import { CATEGORY_STYLES, ZONE_CATEGORY_ORDER } from '../../domain/categories';
import { polygonBounds } from '../../engine/geometry';
import { t, type Locale } from '../../i18n/translations';
import { categoryLabel } from '../../i18n/labels';
import { translateRationale } from '../../i18n/rationale';
import { translateWarning } from '../../i18n/warnings';
import { ObjectVisual } from './ObjectVisual';
import { WaterfrontZone } from './WaterfrontZone';
import { pathStyle } from './pathStyle';

const PX_PER_METER = 12;
const PADDING_M = 6;

export interface StaticPlanRenderProps {
  variant: LayoutVariant;
  plot: Plot;
  locale: Locale;
  showLegend?: boolean;
  showRationale?: boolean;
  showWarnings?: boolean;
  season?: Season;
}

// Non-interactive renderer shared by the export pipeline (and structurally
// mirroring PlanCanvas) so exports never visually drift from the live plan.
export const StaticPlanRender = forwardRef<SVGSVGElement, StaticPlanRenderProps>(function StaticPlanRender(
  { variant, plot, locale, showLegend, showRationale, showWarnings, season },
  ref,
) {
  const bounds = polygonBounds(plot.boundary);
  const legendCategories = ZONE_CATEGORY_ORDER.filter((c) => variant.objects.some((o) => o.category === c) || variant.zones.some((z) => z.category === c));
  const legendRows = showLegend ? legendCategories.length : 0;
  const extraBottom = (showLegend ? legendRows * 1.8 + 2 : 0) + (showWarnings ? Math.min(variant.warnings.length, 6) * 1.6 + 2 : 0);

  const worldW = bounds.maxX - bounds.minX + PADDING_M * 2;
  const worldH = bounds.maxY - bounds.minY + PADDING_M * 2 + extraBottom;
  const viewBox = `${bounds.minX - PADDING_M} ${bounds.minY - PADDING_M} ${worldW} ${worldH}`;

  return (
    <svg
      ref={ref}
      viewBox={viewBox}
      width={worldW * PX_PER_METER}
      height={worldH * PX_PER_METER}
      xmlns="http://www.w3.org/2000/svg"
    >
      <rect x={bounds.minX - PADDING_M} y={bounds.minY - PADDING_M} width={worldW} height={worldH} fill="#fafaf9" />

      <WaterfrontZone plot={plot} themeKey="light" locale={locale} />

      {variant.zones.map((z) => (
        <polygon key={z.id} points={z.boundary.map((p) => `${p.x},${p.y}`).join(' ')} fill={CATEGORY_STYLES[z.category].light.fill} fillOpacity={0.35} stroke={CATEGORY_STYLES[z.category].light.stroke} strokeWidth={0.12} strokeDasharray="0.6,0.4" />
      ))}

      {variant.fences.map((f) => (
        <polygon key={f.id} points={f.points.map((p) => `${p.x},${p.y}`).join(' ')} fill="none" stroke={f.fenceType === 'perimeter' ? '#4a4a4a' : '#8a7050'} strokeWidth={f.fenceType === 'perimeter' ? 0.2 : 0.1} strokeDasharray={f.fenceType === 'perimeter' ? undefined : '0.3,0.3'} />
      ))}

      {variant.paths.map((p) => {
        const style = pathStyle(p);
        return (
          <polyline
            key={p.id}
            points={p.points.map((pt) => `${pt.x},${pt.y}`).join(' ')}
            fill="none"
            stroke={style.stroke}
            strokeWidth={style.strokeWidth}
            strokeLinecap="round"
            strokeDasharray={style.dasharray}
            opacity={style.opacity}
          />
        );
      })}

      <polygon points={plot.boundary.map((p) => `${p.x},${p.y}`).join(' ')} fill="none" stroke="#292524" strokeWidth={0.25} />

      {variant.objects.map((obj) => (
        <g key={obj.id} transform={`translate(${obj.transform.x} ${obj.transform.y}) rotate(${obj.transform.rotationDeg})`}>
          <ObjectVisual obj={obj} themeKey="light" locale={locale} textClassName="select-none" season={season} />
        </g>
      ))}

      {showRationale &&
        variant.objects
          .filter((o) => !o.locked && Array.isArray(o.metadata.rationaleTokens))
          .map((o) => {
            const rationale = translateRationale(locale, o.typeId, o.metadata.rationaleTokens as string[]);
            return (
              <text key={`r-${o.id}`} x={o.transform.x} y={o.transform.y + o.transform.height / 2 + 1.2} fontSize={0.5} textAnchor="middle" fill="#57534e">
                {rationale.length > 55 ? rationale.slice(0, 52) + '…' : rationale}
              </text>
            );
          })}

      <g transform={`translate(${bounds.maxX + PADDING_M * 0.55} ${bounds.minY + PADDING_M * 0.55}) rotate(${plot.northAngleDeg})`}>
        <circle r={1.6} fill="white" stroke="#555" strokeWidth={0.08} />
        <path d="M 0,-1.2 L 0.5,0.6 L 0,0.2 L -0.5,0.6 Z" fill="#333" />
        <text y={-1.9} textAnchor="middle" fontSize={0.8} fill="#333">{t(locale, 'plan.north')}</text>
      </g>

      <g transform={`translate(${bounds.minX} ${bounds.maxY + PADDING_M * 0.75})`}>
        <line x1={0} y1={0} x2={10} y2={0} stroke="#333" strokeWidth={0.15} />
        <text x={5} y={1.1} textAnchor="middle" fontSize={0.7} fill="#333">10 m</text>
      </g>

      {showLegend && (
        <g transform={`translate(${bounds.minX}, ${bounds.maxY + PADDING_M * 1.6})`}>
          {legendCategories.map((c, i) => (
            <g key={c} transform={`translate(0, ${i * 1.8})`}>
              <rect width={1.2} height={1.2} fill={CATEGORY_STYLES[c].light.fill} stroke={CATEGORY_STYLES[c].light.stroke} strokeWidth={0.1} />
              <text x={1.7} y={1} fontSize={0.9} fill="#292524">{categoryLabel(locale, c)}</text>
            </g>
          ))}
        </g>
      )}

      {showWarnings && variant.warnings.length > 0 && (
        <g transform={`translate(${bounds.minX + 16}, ${bounds.maxY + PADDING_M * 1.6})`}>
          <text fontSize={1} fontWeight="bold" fill="#292524">{t(locale, 'plan.warnings')}</text>
          {variant.warnings.slice(0, 6).map((w, i) => {
            const message = translateWarning(locale, w);
            return (
              <text key={w.id} y={1.6 + i * 1.6} fontSize={0.8} fill={w.severity === 'critical' ? '#b91c1c' : w.severity === 'caution' ? '#b45309' : '#57534e'}>
                {message.length > 70 ? message.slice(0, 67) + '…' : message}
              </text>
            );
          })}
        </g>
      )}
    </svg>
  );
});
