import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import type { Warning, WarningSeverity } from '../../domain/types';

const SEVERITY_STYLES: Record<WarningSeverity, string> = {
  critical: 'border-red-300 bg-red-50 text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-300',
  caution: 'border-amber-300 bg-amber-50 text-amber-800 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-300',
  info: 'border-stone-300 bg-stone-50 text-stone-700 dark:border-stone-700 dark:bg-stone-900 dark:text-stone-300',
};

const SEVERITY_LABEL: Record<WarningSeverity, string> = { critical: 'Critical', caution: 'Caution', info: 'Info' };

export function WarningsList({ warnings }: { warnings?: Warning[] }) {
  const project = useProjectStore((s) => s.project);
  const select = useProjectStore((s) => s.select);
  const variant = getActiveVariant(project);
  const list = warnings ?? variant?.warnings ?? [];

  if (list.length === 0) {
    return <p className="p-3 text-xs text-stone-500 dark:text-stone-400">No warnings on this layout.</p>;
  }

  return (
    <ul className="space-y-1.5 p-3">
      {list.map((w) => (
        <li
          key={w.id}
          onClick={() => w.objectIds.length > 0 && select(w.objectIds)}
          className={`cursor-pointer rounded-md border px-2.5 py-1.5 text-xs ${SEVERITY_STYLES[w.severity]}`}
        >
          <span className="mr-1.5 font-semibold">{SEVERITY_LABEL[w.severity]}:</span>
          {w.message}
        </li>
      ))}
    </ul>
  );
}
