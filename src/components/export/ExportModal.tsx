import { useRef, useState } from 'react';
import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { StaticPlanRender } from '../canvas/StaticPlanRender';
import { exportSvgAsPng, exportSvgAsPdf, exportProjectAsJson } from '../../engine/exporters';

type Format = 'png' | 'pdf' | 'json';

export function ExportModal() {
  const isOpen = useProjectStore((s) => s.isExportOpen);
  const setExportOpen = useProjectStore((s) => s.setExportOpen);
  const project = useProjectStore((s) => s.project);
  const visualizationMode = useProjectStore((s) => s.visualizationMode);
  const season = useProjectStore((s) => s.season);
  const variant = getActiveVariant(project);
  const [format, setFormat] = useState<Format>('png');
  const [includeLegend, setIncludeLegend] = useState(true);
  const [includeRationale, setIncludeRationale] = useState(false);
  const [includeWarnings, setIncludeWarnings] = useState(true);
  const [exporting, setExporting] = useState(false);
  const svgRef = useRef<SVGSVGElement>(null);

  if (!isOpen || !variant) return null;

  const hasUnresolvedCritical = variant.warnings.some((w) => w.severity === 'critical');
  const baseName = project.name.toLowerCase().replace(/[^a-z0-9]+/g, '-');

  const handleExport = async () => {
    setExporting(true);
    try {
      if (format === 'json') {
        exportProjectAsJson(project, `${baseName}.json`);
      } else if (svgRef.current) {
        if (format === 'png') await exportSvgAsPng(svgRef.current, `${baseName}-${variant.strategyLabel.toLowerCase().replace(/\s+/g, '-')}.png`);
        else await exportSvgAsPdf(svgRef.current, `${baseName}-${variant.strategyLabel.toLowerCase().replace(/\s+/g, '-')}.pdf`);
      }
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setExportOpen(false)}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-lg bg-white shadow-xl dark:bg-stone-900"
      >
        <div className="flex items-center justify-between border-b border-stone-200 px-4 py-3 dark:border-stone-800">
          <h2 className="text-sm font-semibold text-stone-800 dark:text-stone-100">Export — {variant.strategyLabel}</h2>
          <button onClick={() => setExportOpen(false)} className="text-stone-500 hover:text-stone-800 dark:hover:text-stone-100">✕</button>
        </div>

        <div className="flex flex-1 overflow-hidden">
          <div className="w-56 shrink-0 space-y-4 border-r border-stone-200 p-4 text-xs dark:border-stone-800">
            <div className="flex gap-1.5">
              {(['png', 'pdf', 'json'] as Format[]).map((f) => (
                <button
                  key={f}
                  onClick={() => setFormat(f)}
                  className={`rounded px-2.5 py-1 uppercase ${format === f ? 'bg-emerald-700 text-white dark:bg-emerald-600' : 'border border-stone-300 text-stone-600 dark:border-stone-700 dark:text-stone-300'}`}
                >
                  {f}
                </button>
              ))}
            </div>

            {format !== 'json' && (
              <div className="space-y-2">
                <label className="flex items-center gap-2"><input type="checkbox" checked={includeLegend} onChange={(e) => setIncludeLegend(e.target.checked)} /> Legend</label>
                <label className="flex items-center gap-2"><input type="checkbox" checked={includeRationale} onChange={(e) => setIncludeRationale(e.target.checked)} /> Rationale callouts</label>
                <label className="flex items-center gap-2"><input type="checkbox" checked={includeWarnings} onChange={(e) => setIncludeWarnings(e.target.checked)} /> Warnings appendix</label>
              </div>
            )}

            {hasUnresolvedCritical && (
              <p className="rounded border border-red-300 bg-red-50 p-2 text-[11px] text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
                This plan has unresolved critical warnings. They will be noted on the export.
              </p>
            )}

            <button
              onClick={handleExport}
              disabled={exporting}
              className="w-full rounded-md bg-emerald-700 py-2 font-medium text-white hover:bg-emerald-800 disabled:opacity-50 dark:bg-emerald-600 dark:hover:bg-emerald-500"
            >
              {exporting ? 'Exporting…' : `Download ${format.toUpperCase()}`}
            </button>
          </div>

          <div className="flex-1 overflow-auto bg-stone-100 p-4 dark:bg-stone-950">
            {format === 'json' ? (
              <pre className="max-h-full overflow-auto rounded bg-white p-3 text-[10px] dark:bg-stone-900 dark:text-stone-300">
                {JSON.stringify(project, null, 2).slice(0, 4000)}
              </pre>
            ) : (
              <StaticPlanRender
                ref={svgRef}
                variant={variant}
                plot={project.plot}
                showLegend={includeLegend}
                showRationale={includeRationale}
                showWarnings={includeWarnings}
                season={visualizationMode === 'seasonal' ? season : undefined}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
