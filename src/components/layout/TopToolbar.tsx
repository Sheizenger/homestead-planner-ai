import { useProjectStore } from '../../state/projectStore';
import type { VisualizationMode } from '../../domain/types';
import { SEASONS } from '../../domain/seasons';
import { LOCALES, LOCALE_NAMES, t } from '../../i18n/translations';
import { seasonLabel, planningModeLabel } from '../../i18n/labels';

const MODES: { value: VisualizationMode; key: string }[] = [
  { value: 'schematic', key: 'mode.schematic' },
  { value: 'design', key: 'mode.design' },
  { value: 'utilities', key: 'mode.utilities' },
  { value: 'seasonal', key: 'mode.seasonal' },
  { value: 'rationale', key: 'mode.rationale' },
];

export function TopToolbar() {
  const project = useProjectStore((s) => s.project);
  const locale = useProjectStore((s) => s.locale);
  const setLocale = useProjectStore((s) => s.setLocale);
  const visualizationMode = useProjectStore((s) => s.visualizationMode);
  const setVisualizationMode = useProjectStore((s) => s.setVisualizationMode);
  const season = useProjectStore((s) => s.season);
  const setSeason = useProjectStore((s) => s.setSeason);
  const view = useProjectStore((s) => s.view);
  const setView = useProjectStore((s) => s.setView);
  const setActiveVariant = useProjectStore((s) => s.setActiveVariant);
  const zoom = useProjectStore((s) => s.zoom);
  const setZoom = useProjectStore((s) => s.setZoom);
  const snapToGrid = useProjectStore((s) => s.snapToGrid);
  const toggleSnap = useProjectStore((s) => s.toggleSnap);
  const showLegend = useProjectStore((s) => s.showLegend);
  const toggleLegend = useProjectStore((s) => s.toggleLegend);
  const undo = useProjectStore((s) => s.undo);
  const redo = useProjectStore((s) => s.redo);
  const theme = useProjectStore((s) => s.theme);
  const setTheme = useProjectStore((s) => s.setTheme);
  const setExportOpen = useProjectStore((s) => s.setExportOpen);
  const setCostOpen = useProjectStore((s) => s.setCostOpen);
  const setProjectsOpen = useProjectStore((s) => s.setProjectsOpen);
  const regenerateVariant = useProjectStore((s) => s.regenerateVariant);

  return (
    <div className="flex items-center gap-3 border-b border-stone-200 bg-white px-3 py-2 text-xs dark:border-stone-800 dark:bg-stone-900">
      <button
        onClick={() => setProjectsOpen(true)}
        className="max-w-[10rem] truncate rounded-md border border-stone-300 px-2 py-1 font-medium text-stone-600 hover:bg-stone-100 dark:border-stone-700 dark:text-stone-300 dark:hover:bg-stone-800"
        title={project.name}
      >
        {project.name}
      </button>

      <div className="mx-1 h-5 w-px bg-stone-200 dark:bg-stone-800" />

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
            title={planningModeLabel(locale, v.mode)}
          >
            {planningModeLabel(locale, v.mode)}
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
          {t(locale, 'toolbar.compare')}
        </button>
      </div>

      {view === 'workspace' && (
        <button
          onClick={() => regenerateVariant(project.activeVariantId)}
          className="rounded-md border border-stone-300 px-2 py-1 text-stone-600 hover:bg-stone-100 dark:border-stone-700 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          {t(locale, 'toolbar.reroll')}
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
            {t(locale, m.key)}
          </button>
        ))}
      </div>

      {visualizationMode === 'seasonal' && (
        <div className="flex items-center gap-1 rounded-md border border-stone-300 p-0.5 dark:border-stone-700">
          {SEASONS.map((s) => (
            <button
              key={s}
              onClick={() => setSeason(s)}
              className={`rounded px-2 py-1 font-medium transition-colors ${
                season === s
                  ? 'bg-emerald-700 text-white dark:bg-emerald-600'
                  : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'
              }`}
            >
              {seasonLabel(locale, s)}
            </button>
          ))}
        </div>
      )}

      <div className="mx-1 h-5 w-px bg-stone-200 dark:bg-stone-800" />

      <button onClick={undo} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
        {t(locale, 'toolbar.undo')}
      </button>
      <button onClick={redo} className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800">
        {t(locale, 'toolbar.redo')}
      </button>

      <button
        onClick={toggleSnap}
        className={`rounded px-2 py-1 font-medium ${snapToGrid ? 'bg-stone-800 text-white dark:bg-stone-200 dark:text-stone-900' : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'}`}
      >
        {t(locale, 'toolbar.snap')}
      </button>

      <button
        onClick={toggleLegend}
        className={`rounded px-2 py-1 font-medium ${showLegend ? 'bg-stone-800 text-white dark:bg-stone-200 dark:text-stone-900' : 'text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800'}`}
      >
        {t(locale, 'toolbar.legend')}
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

        <select
          value={locale}
          onChange={(e) => setLocale(e.target.value as typeof locale)}
          title={t(locale, 'toolbar.language')}
          className="rounded border border-stone-300 bg-transparent px-1 py-1 text-stone-600 dark:border-stone-700 dark:text-stone-300"
        >
          {LOCALES.map((l) => (
            <option key={l} value={l}>{LOCALE_NAMES[l]}</option>
          ))}
        </select>

        <button
          onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}
          className="rounded px-2 py-1 text-stone-600 hover:bg-stone-100 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          {theme === 'light' ? t(locale, 'toolbar.darkMode') : t(locale, 'toolbar.lightMode')}
        </button>

        <button
          onClick={() => setCostOpen(true)}
          className="rounded-md border border-stone-300 px-3 py-1.5 font-medium text-stone-600 hover:bg-stone-100 dark:border-stone-700 dark:text-stone-300 dark:hover:bg-stone-800"
        >
          {t(locale, 'toolbar.costEstimate')}
        </button>

        <button
          onClick={() => setExportOpen(true)}
          className="rounded-md bg-emerald-700 px-3 py-1.5 font-medium text-white hover:bg-emerald-800 dark:bg-emerald-600 dark:hover:bg-emerald-500"
        >
          {t(locale, 'toolbar.export')}
        </button>
      </div>
    </div>
  );
}
