import { useProjectStore, getActiveVariant, categoryLabel } from '../../state/projectStore';
import { ZONE_CATEGORY_ORDER } from '../../domain/categories';

export function BottomStatusBar() {
  const project = useProjectStore((s) => s.project);
  const variant = getActiveVariant(project);
  const layerVisibility = useProjectStore((s) => s.layerVisibility);
  const toggleLayerVisibility = useProjectStore((s) => s.toggleLayerVisibility);
  const snapToGrid = useProjectStore((s) => s.snapToGrid);
  const gridSize = useProjectStore((s) => s.gridSize);
  const setGridSize = useProjectStore((s) => s.setGridSize);
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);

  const selected = variant?.objects.find((o) => o.id === selectedObjectIds[0]);
  const critical = variant?.warnings.filter((w) => w.severity === 'critical').length ?? 0;
  const caution = variant?.warnings.filter((w) => w.severity === 'caution').length ?? 0;

  return (
    <div className="flex items-center gap-3 overflow-x-auto border-t border-stone-200 bg-white px-3 py-1.5 text-[11px] text-stone-600 dark:border-stone-800 dark:bg-stone-900 dark:text-stone-300">
      <div className="flex shrink-0 items-center gap-1.5">
        {ZONE_CATEGORY_ORDER.map((c) => (
          <button
            key={c}
            onClick={() => toggleLayerVisibility(c)}
            className={`rounded px-1.5 py-0.5 ${layerVisibility[c] === false ? 'text-stone-400 line-through dark:text-stone-600' : 'bg-stone-100 dark:bg-stone-800'}`}
            title={`Toggle ${categoryLabel(c)} layer`}
          >
            {categoryLabel(c)}
          </button>
        ))}
      </div>

      <div className="mx-1 h-4 w-px shrink-0 bg-stone-200 dark:bg-stone-800" />

      <span className="shrink-0">Grid: {snapToGrid ? `${gridSize} m` : 'off'}</span>
      <select
        value={gridSize}
        onChange={(e) => setGridSize(Number(e.target.value))}
        className="shrink-0 rounded border border-stone-300 bg-transparent px-1 dark:border-stone-700"
      >
        {[0.5, 1, 2, 5].map((g) => (
          <option key={g} value={g}>{g} m</option>
        ))}
      </select>

      {selected && (
        <span className="shrink-0">
          {selected.label}: {selected.transform.width.toFixed(1)}×{selected.transform.height.toFixed(1)} m @ ({selected.transform.x.toFixed(1)}, {selected.transform.y.toFixed(1)})
        </span>
      )}

      <div className="ml-auto flex shrink-0 items-center gap-3">
        {variant && (
          <>
            <span>{variant.analytics.allocatedAreaM2.toFixed(0)} / {variant.analytics.totalAreaM2.toFixed(0)} m² used</span>
            {critical > 0 && <span className="font-medium text-red-700 dark:text-red-400">{critical} critical</span>}
            {caution > 0 && <span className="font-medium text-amber-700 dark:text-amber-400">{caution} caution</span>}
          </>
        )}
      </div>
    </div>
  );
}
