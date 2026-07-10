import { useProjectStore } from '../../state/projectStore';
import { CATEGORY_STYLES } from '../../domain/categories';
import { polygonBounds } from '../../engine/geometry';
import { computeCostEstimate, findRegion } from '../../engine/costs';
import { CURRENCIES, CURRENCY_SYMBOLS, convertFromUsd } from '../../domain/costData';
import type { LayoutVariant } from '../../domain/types';
import { t } from '../../i18n/translations';
import { planningModeLabel } from '../../i18n/labels';
import { translateRationale } from '../../i18n/rationale';

function MiniPlan({ variant, boundary, onObjectClick }: { variant: LayoutVariant; boundary: { x: number; y: number }[]; onObjectClick?: (id: string) => void }) {
  const bounds = polygonBounds(boundary);
  const pad = 4;
  const w = bounds.maxX - bounds.minX + pad * 2;
  const h = bounds.maxY - bounds.minY + pad * 2;

  return (
    <svg viewBox={`${bounds.minX - pad} ${bounds.minY - pad} ${w} ${h}`} className="w-full rounded border border-stone-200 bg-stone-50 dark:border-stone-800 dark:bg-stone-950" style={{ aspectRatio: `${w} / ${h}` }}>
      {variant.zones.map((z) => (
        <polygon key={z.id} points={z.boundary.map((p) => `${p.x},${p.y}`).join(' ')} fill={CATEGORY_STYLES[z.category].light.fill} fillOpacity={0.35} stroke={CATEGORY_STYLES[z.category].light.stroke} strokeWidth={0.15} strokeDasharray="0.6,0.4" />
      ))}
      <polygon points={boundary.map((p) => `${p.x},${p.y}`).join(' ')} fill="none" stroke="#555" strokeWidth={0.3} />
      {variant.objects.map((o) => (
        <g
          key={o.id}
          transform={`translate(${o.transform.x} ${o.transform.y}) rotate(${o.transform.rotationDeg})`}
          onClick={() => onObjectClick?.(o.id)}
          className={onObjectClick ? 'cursor-copy' : undefined}
        >
          <rect
            x={-o.transform.width / 2}
            y={-o.transform.height / 2}
            width={o.transform.width}
            height={o.transform.height}
            fill={CATEGORY_STYLES[o.category as keyof typeof CATEGORY_STYLES]?.light.fill ?? '#ddd'}
            stroke={CATEGORY_STYLES[o.category as keyof typeof CATEGORY_STYLES]?.light.stroke ?? '#888'}
            strokeWidth={0.15}
          />
        </g>
      ))}
    </svg>
  );
}

export function VariantComparisonView() {
  const project = useProjectStore((s) => s.project);
  const locale = useProjectStore((s) => s.locale);
  const setActiveVariant = useProjectStore((s) => s.setActiveVariant);
  const setView = useProjectStore((s) => s.setView);
  const copyObjectToActive = useProjectStore((s) => s.copyObjectToActive);
  const costRegionId = useProjectStore((s) => s.costRegionId);
  const customLandPriceUsd = useProjectStore((s) => s.customLandPriceUsd);
  const setCostOpen = useProjectStore((s) => s.setCostOpen);

  const baseRegion = findRegion(costRegionId);
  const region = baseRegion.id === 'custom' ? { ...baseRegion, landPricePerM2Usd: customLandPriceUsd } : baseRegion;

  return (
    <div className="h-full overflow-y-auto bg-stone-100 p-4 dark:bg-stone-950">
      <p className="mb-3 text-xs text-stone-500 dark:text-stone-400">{t(locale, 'compare.hint')}</p>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
        {project.variants.map((v) => {
          const isActive = v.id === project.activeVariantId;
          const cost = computeCostEstimate(v, region);
          const rationaleItems = v.objects
            .filter((o) => !o.locked && Array.isArray(o.metadata.rationaleTokens))
            .slice(0, 3)
            .map((o) => translateRationale(locale, o.typeId, o.metadata.rationaleTokens as string[]));
          return (
            <div key={v.id} className={`rounded-lg border p-3 ${isActive ? 'border-emerald-600 bg-white dark:bg-stone-900' : 'border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900'}`}>
              <div className="mb-2 flex items-center justify-between">
                <h3 className="text-sm font-semibold text-stone-800 dark:text-stone-100">{planningModeLabel(locale, v.mode)}</h3>
                {isActive ? (
                  <span className="rounded bg-emerald-700 px-2 py-0.5 text-[10px] font-medium text-white dark:bg-emerald-600">{t(locale, 'compare.active')}</span>
                ) : (
                  <button
                    onClick={() => {
                      setActiveVariant(v.id);
                      setView('workspace');
                    }}
                    className="rounded border border-stone-300 px-2 py-0.5 text-[10px] hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
                  >
                    {t(locale, 'compare.makeActive')}
                  </button>
                )}
              </div>

              <MiniPlan
                variant={v}
                boundary={project.plot.boundary}
                onObjectClick={isActive ? undefined : (id) => copyObjectToActive(v.id, id)}
              />

              <div className="mt-2 grid grid-cols-2 gap-1.5 text-[11px] text-stone-600 dark:text-stone-300">
                <span>{t(locale, 'compare.allocated', { value: v.analytics.allocatedAreaM2.toFixed(0) })}</span>
                <span>{t(locale, 'compare.foodScore', { value: v.analytics.estimatedFoodProductionScore.toFixed(0) })}</span>
                <span>{t(locale, 'compare.maintenance', { value: v.analytics.maintenanceComplexityScore.toFixed(0) })}</span>
                <span>{t(locale, 'compare.warnings', { value: v.warnings.length })}</span>
              </div>

              <button
                onClick={() => {
                  setActiveVariant(v.id);
                  setCostOpen(true);
                }}
                className="mt-2 w-full rounded-md border border-stone-200 px-2 py-1.5 text-left text-[11px] hover:bg-stone-50 dark:border-stone-800 dark:hover:bg-stone-800"
                title={t(locale, 'compare.openCostBreakdown')}
              >
                <span className="text-stone-500 dark:text-stone-400">{t(locale, 'compare.estTotal')}</span>
                {CURRENCIES.map((c, i) => (
                  <span key={c} className="font-medium text-stone-800 dark:text-stone-100">
                    {i > 0 && ' / '}
                    {CURRENCY_SYMBOLS[c]}
                    {convertFromUsd(cost.totalUpfrontUsd, c).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                  </span>
                ))}
              </button>

              {rationaleItems.length > 0 && (
                <ul className="mt-2 space-y-1 text-[11px] text-stone-500 dark:text-stone-400">
                  {rationaleItems.map((r, i) => (
                    <li key={i} className="line-clamp-2">• {r}</li>
                  ))}
                </ul>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
