import { useProjectStore, getActiveVariant, categoryLabel } from '../../state/projectStore';
import { CATEGORY_STYLES } from '../../domain/categories';

export function AnalyticsPanel() {
  const project = useProjectStore((s) => s.project);
  const variant = getActiveVariant(project);
  if (!variant) return null;
  const a = variant.analytics;
  const utilization = a.totalAreaM2 > 0 ? (a.allocatedAreaM2 / a.totalAreaM2) * 100 : 0;

  return (
    <div className="space-y-3 p-3 text-xs">
      <div className="grid grid-cols-2 gap-2">
        <Stat label="Total plot" value={`${a.totalAreaM2.toFixed(0)} m²`} />
        <Stat label="Allocated" value={`${a.allocatedAreaM2.toFixed(0)} m²`} />
        <Stat label="Unallocated" value={`${a.unallocatedAreaM2.toFixed(0)} m²`} />
        <Stat label="Utilization" value={`${utilization.toFixed(0)}%`} />
        <Stat label="Food production" value={`${a.estimatedFoodProductionScore.toFixed(0)} / 100`} />
        <Stat label="Maintenance load" value={`${a.maintenanceComplexityScore.toFixed(0)} / 100`} />
      </div>

      <div>
        <h4 className="mb-1.5 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">
          Area by category
        </h4>
        <div className="space-y-1">
          {a.byCategory.map((c) => (
            <div key={c.category} className="flex items-center gap-2">
              <span
                className="h-2.5 w-2.5 shrink-0 rounded-sm"
                style={{ backgroundColor: CATEGORY_STYLES[c.category].light.stroke }}
              />
              <span className="w-24 shrink-0 text-stone-600 dark:text-stone-300">{categoryLabel(c.category)}</span>
              <div className="h-1.5 flex-1 rounded-full bg-stone-200 dark:bg-stone-800">
                <div
                  className="h-1.5 rounded-full"
                  style={{ width: `${Math.min(100, c.percent)}%`, backgroundColor: CATEGORY_STYLES[c.category].light.stroke }}
                />
              </div>
              <span className="w-14 shrink-0 text-right text-stone-500 dark:text-stone-400">{c.areaM2.toFixed(0)} m²</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-stone-200 bg-white px-2 py-1.5 dark:border-stone-800 dark:bg-stone-900">
      <div className="text-[10px] text-stone-500 dark:text-stone-400">{label}</div>
      <div className="text-sm font-semibold text-stone-800 dark:text-stone-100">{value}</div>
    </div>
  );
}
