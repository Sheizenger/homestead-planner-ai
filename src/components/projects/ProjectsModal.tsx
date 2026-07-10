import { useRef, useState } from 'react';
import { useProjectStore } from '../../state/projectStore';
import { t } from '../../i18n/translations';

export function ProjectsModal() {
  const isOpen = useProjectStore((s) => s.isProjectsOpen);
  const setProjectsOpen = useProjectStore((s) => s.setProjectsOpen);
  const project = useProjectStore((s) => s.project);
  const locale = useProjectStore((s) => s.locale);
  const getSavedProjects = useProjectStore((s) => s.getSavedProjects);
  const switchToProject = useProjectStore((s) => s.switchToProject);
  const deleteSavedProject = useProjectStore((s) => s.deleteSavedProject);
  const newProject = useProjectStore((s) => s.newProject);
  const generate = useProjectStore((s) => s.generate);
  const importProjectFromJson = useProjectStore((s) => s.importProjectFromJson);

  const [newName, setNewName] = useState('New Homestead');
  const [newWidth, setNewWidth] = useState(40);
  const [newHeight, setNewHeight] = useState(30);
  const [importError, setImportError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!isOpen) return null;

  const saved = getSavedProjects();

  const handleCreate = () => {
    newProject(newName.trim() || 'New Homestead', newWidth, newHeight);
    generate();
  };

  const handleImportFile = async (file: File) => {
    const text = await file.text();
    const result = importProjectFromJson(text);
    setImportError(result.ok ? null : result.error);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setProjectsOpen(false)}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[85vh] w-full max-w-lg flex-col overflow-hidden rounded-lg bg-white shadow-xl dark:bg-stone-900"
      >
        <div className="flex items-center justify-between border-b border-stone-200 px-4 py-3 dark:border-stone-800">
          <h2 className="text-sm font-semibold text-stone-800 dark:text-stone-100">{t(locale, 'projects.title')}</h2>
          <button onClick={() => setProjectsOpen(false)} className="text-stone-500 hover:text-stone-800 dark:hover:text-stone-100">✕</button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 text-xs">
          <div className="mb-4 rounded-md border border-stone-200 p-3 dark:border-stone-800">
            <h3 className="mb-2 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">{t(locale, 'projects.newProject')}</h3>
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col gap-1 text-stone-600 dark:text-stone-300">
                {t(locale, 'projects.name')}
                <input
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-36 rounded border border-stone-300 px-2 py-1 dark:border-stone-700 dark:bg-stone-800"
                />
              </label>
              <label className="flex flex-col gap-1 text-stone-600 dark:text-stone-300">
                {t(locale, 'projects.width')}
                <input
                  type="number"
                  min={10}
                  value={newWidth}
                  onChange={(e) => setNewWidth(Number(e.target.value))}
                  className="w-20 rounded border border-stone-300 px-2 py-1 text-right dark:border-stone-700 dark:bg-stone-800"
                />
              </label>
              <label className="flex flex-col gap-1 text-stone-600 dark:text-stone-300">
                {t(locale, 'projects.depth')}
                <input
                  type="number"
                  min={10}
                  value={newHeight}
                  onChange={(e) => setNewHeight(Number(e.target.value))}
                  className="w-20 rounded border border-stone-300 px-2 py-1 text-right dark:border-stone-700 dark:bg-stone-800"
                />
              </label>
              <button
                onClick={handleCreate}
                className="rounded-md bg-emerald-700 px-3 py-1.5 font-medium text-white hover:bg-emerald-800 dark:bg-emerald-600 dark:hover:bg-emerald-500"
              >
                {t(locale, 'projects.create')}
              </button>
            </div>
          </div>

          <div className="mb-4 rounded-md border border-stone-200 p-3 dark:border-stone-800">
            <h3 className="mb-2 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">{t(locale, 'projects.importFromFile')}</h3>
            <input
              ref={fileInputRef}
              type="file"
              accept="application/json"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) handleImportFile(file);
                e.target.value = '';
              }}
              className="text-stone-600 dark:text-stone-300"
            />
            {importError && <p className="mt-1.5 text-[11px] text-red-700 dark:text-red-400">{importError}</p>}
          </div>

          <div>
            <h3 className="mb-2 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">
              {t(locale, 'projects.savedProjects', { count: saved.length })}
            </h3>
            {saved.length === 0 && <p className="text-stone-500 dark:text-stone-400">{t(locale, 'projects.nothingSaved')}</p>}
            <ul className="space-y-1.5">
              {saved.map((p) => (
                <li
                  key={p.id}
                  className={`flex items-center justify-between rounded-md border px-2.5 py-1.5 ${
                    p.id === project.id
                      ? 'border-emerald-600 bg-emerald-50 dark:bg-emerald-950'
                      : 'border-stone-200 dark:border-stone-800'
                  }`}
                >
                  <div>
                    <div className="font-medium text-stone-800 dark:text-stone-100">{p.name}</div>
                    <div className="text-[10px] text-stone-500 dark:text-stone-400">
                      {new Date(p.updatedAt).toLocaleString()}
                    </div>
                  </div>
                  <div className="flex gap-1.5">
                    {p.id !== project.id && (
                      <button
                        onClick={() => switchToProject(p.id)}
                        className="rounded border border-stone-300 px-2 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
                      >
                        {t(locale, 'projects.open')}
                      </button>
                    )}
                    <button
                      onClick={() => deleteSavedProject(p.id)}
                      className="rounded border border-red-300 px-2 py-1 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950"
                    >
                      {t(locale, 'projects.delete')}
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>

          <p className="mt-4 text-[11px] text-stone-500 dark:text-stone-400">{t(locale, 'projects.footerNote')}</p>
        </div>
      </div>
    </div>
  );
}
