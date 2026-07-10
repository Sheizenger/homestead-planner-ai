import { useEffect } from 'react';
import { useProjectStore } from './state/projectStore';
import { BriefForm } from './components/panels/BriefForm';
import { RightPanel } from './components/layout/RightPanel';
import { TopToolbar } from './components/layout/TopToolbar';
import { BottomStatusBar } from './components/layout/BottomStatusBar';
import { PlanCanvas } from './components/canvas/PlanCanvas';
import { VariantComparisonView } from './components/comparison/VariantComparisonView';
import { ExportModal } from './components/export/ExportModal';
import { CostModal } from './components/cost/CostModal';
import { ProjectsModal } from './components/projects/ProjectsModal';

function useKeyboardShortcuts() {
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);
  const deleteObjects = useProjectStore((s) => s.deleteObjects);
  const duplicateObjects = useProjectStore((s) => s.duplicateObjects);
  const updateObjectTransform = useProjectStore((s) => s.updateObjectTransform);
  const project = useProjectStore((s) => s.project);
  const gridSize = useProjectStore((s) => s.gridSize);
  const undo = useProjectStore((s) => s.undo);
  const redo = useProjectStore((s) => s.redo);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return;

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
        return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'd') {
        e.preventDefault();
        if (selectedObjectIds.length > 0) duplicateObjects(selectedObjectIds);
        return;
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedObjectIds.length > 0) deleteObjects(selectedObjectIds);
        return;
      }
      if (selectedObjectIds.length === 1 && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
        e.preventDefault();
        const variant = project.variants.find((v) => v.id === project.activeVariantId);
        const obj = variant?.objects.find((o) => o.id === selectedObjectIds[0]);
        if (!obj || obj.locked) return;
        const step = gridSize;
        const delta = { ArrowUp: { x: 0, y: -step }, ArrowDown: { x: 0, y: step }, ArrowLeft: { x: -step, y: 0 }, ArrowRight: { x: step, y: 0 } }[e.key]!;
        updateObjectTransform(obj.id, { x: obj.transform.x + delta.x, y: obj.transform.y + delta.y });
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [selectedObjectIds, deleteObjects, duplicateObjects, updateObjectTransform, project, gridSize, undo, redo]);
}

function App() {
  const theme = useProjectStore((s) => s.theme);
  const view = useProjectStore((s) => s.view);
  const project = useProjectStore((s) => s.project);
  const generate = useProjectStore((s) => s.generate);
  useKeyboardShortcuts();

  useEffect(() => {
    document.documentElement.classList.toggle('dark', theme === 'dark');
  }, [theme]);

  useEffect(() => {
    if (project.variants.length === 0) generate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="flex h-screen w-screen flex-col bg-stone-50 text-stone-900 dark:bg-stone-950 dark:text-stone-100">
      <TopToolbar />
      <div className="flex min-h-0 flex-1">
        <aside className="w-72 shrink-0 border-r border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900">
          <BriefForm />
        </aside>
        <main className="min-w-0 flex-1">{view === 'workspace' ? <PlanCanvas /> : <VariantComparisonView />}</main>
        <aside className="w-72 shrink-0 border-l border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900">
          <RightPanel />
        </aside>
      </div>
      <BottomStatusBar />
      <ExportModal />
      <CostModal />
      <ProjectsModal />
    </div>
  );
}

export default App;
