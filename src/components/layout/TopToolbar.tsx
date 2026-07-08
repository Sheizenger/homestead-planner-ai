import { useProjectStore } from '../../state/projectStore';
import type { VisualizationMode } from '../../domain/types';

const MODES: { value: VisualizationMode; label: string }[] = [
  { value: 'schematic', label: 'Schematic' },
  { value: 'design', label: 'Design' },
  { value: 'utilities', label: 'Utilities' },
  { value: 'seasonal', label: 'Seasonal' },
  { value: 'rationale', label: 'Rationale' },
];

export function TopToolbar() {
  const project = useProjectStore((s) => s.project);
  const visualizationMode = useProjectStore((s) => s.visualizationMode);
  const setVisualizationMode = useProjectStore((s) => s.setVisualizationMode);
  const view = useProjectStore((s) => s.view);
  const setView = useProjectStore((s) => s.setView);
  const setActiveVariant = useProjectStore((s) => s.setActiveVariant);
  const zoom = useProjectStore((s) => s.zoom);
  const setZoom = useProjectStore((s) => s.setZoom);
  const snapToGrid = useProjectStore((s) => s.snapToGrid);
  const toggleSnap = useProjectStore((s) => s.toggleSnap);
  const undo = useProjectStore((s) => s.undo);
  const redo = useProjectStore((s) => s.redo);
  const theme = useProjectStore((s) => s.theme);
  const setTheme = useProjectStore((s) => s.setTheme);
  const setExportOpen = useProjectStore((s) => s.setExportOpen);
  const setCostOpen = useProjectStore((s) => s.setCostOpen);
  const regenerateVariant = useProjectStore((s) => s.regenerateVariant);

  return (
    <div className="flex items-center gap-3 border-b border-stone-200 bg-white px-3 py-2 text-xs dark:border-stone-800 dark:bg-stone-900">
      <div className="flex items-center gap-1 rounded-md border border-stone-300 p-0.5 dark:border-stone-700">
        {project.variants.map((v) => (
          <button
            key={v.id}
            onClick={() => {
              setActiveVariant(v.id);
              setView('workspace');
            }}
            className={`rounded px-2 py-1 font-medium transition-colors ${
              view === 'workspace' && project.activeVariantId === v.id
                ? 'bg-emerald-700 text-white dark:bg-emerald-600'
                : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'
            }`}
            title={v.strategyLabel}
          >
            {v.strategyLabel}
          </button>
        ))}
        <button
          onClick={() => setView('comparison')}
          className={`rounded px-2 py-1 font-medium transition-colors ${
            view === 'comparison'
              ? 'bg-emerald-700 text-white dark:bg-emerald-600'
              : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'
          }`}
        >
          Compare
        </button>
      </div>

      {view === 'workspace' && (
        <button
          onClick={() => regenerateVariant(project.activeVariantId)}
          className="rounded-md border border-stone-300 px-2 py-1 text-stone-600 hover:bg-stone-100 dark:border-stone-700 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          Re-roll
        </button>
      )}

      <div className="mx-1 h-5 w-px bg-stone-200 dark:bg-stone-800" />

      <div className="flex items-center gap-1">
        {MODES.map((m) => (
          <button
            key={m.value}
            onClick={() => setVisualizationMode(m.value)}
            className={`rounded px-2 py-1 font-medium transition-colors ${
              visualizationMode === m.value
                ? 'bg-stone-800 text-white dark:bg-stone-200 dark:text-stone-900'
                : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'
            }`}
          >
            {m.label}
          </button>
        ))}
      </div>

      <div className="mx-1 h-5 w-px bg-stone-200 dark:bg-stone-800" />

      <button onClick={undo} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
        Undo
      </button>
      <button onClick={redo} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
        Redo
      </button>

      <button
        onClick={toggleSnap}
        className={`rounded px-2 py-1 font-medium ${snapToGrid ? 'bg-stone-800 text-white dark:bg-stone-200 dark:text-stone-900' : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'}`}
      >
        Snap
      </button>

      <div className="ml-auto flex items-center gap-2">
        <button onClick={() => setZoom(zoom - 0.15)} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
          −
        </button>
        <span className="w-10 text-center text-stone-500 dark:text-stone-400">{Math.round(zoom * 100)}%</span>
        <button onClick={() => setZoom(zoom + 0.15)} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
          +
        </button>

        <div className="mx-1 h-5 w-px bg-stone-200 dark:bg-stone-800" />

        <button
          onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}
          className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          {theme === 'light' ? 'Dark mode' : 'Light mode'}
        </button>

        <button
          onClick={() => setCostOpen(true)}
          className="rounded-md border border-stone-300 px-3 py-1.5 font-medium text-stone-600 hover:bg-stone-100 dark:border-stone-700 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          Cost Estimate
        </button>

        <button
          onClick={() => setExportOpen(true)}
          className="rounded-md bg-emerald-700 px-3 py-1.5 font-medium text-white hover:bg-emerald-800 dark:bg-emerald-600 dark:hover:bg-emerald-500"
        >
          Export
        </button>
      </div>
    </div>
  );
}
