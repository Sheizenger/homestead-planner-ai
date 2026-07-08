import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';

export function ObjectPropertiesPanel() {
  const project = useProjectStore((s) => s.project);
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);
  const updateObjectTransform = useProjectStore((s) => s.updateObjectTransform);
  const toggleLock = useProjectStore((s) => s.toggleLock);
  const deleteObjects = useProjectStore((s) => s.deleteObjects);
  const duplicateObjects = useProjectStore((s) => s.duplicateObjects);
  const variant = getActiveVariant(project);

  if (!variant || selectedObjectIds.length === 0) {
    return <p className="p-3 text-xs text-stone-500 dark:text-stone-400">Select an object on the plan to inspect and edit it.</p>;
  }

  if (selectedObjectIds.length > 1) {
    const objs = variant.objects.filter((o) => selectedObjectIds.includes(o.id));
    return (
      <div className="space-y-3 p-3 text-xs">
        <p className="text-stone-600 dark:text-stone-300">{objs.length} objects selected</p>
        <div className="flex gap-2">
          <button
            onClick={() => duplicateObjects(selectedObjectIds)}
            className="rounded-md border border-stone-300 px-2.5 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
          >
            Duplicate
          </button>
          <button
            onClick={() => deleteObjects(selectedObjectIds)}
            className="rounded-md border border-red-300 px-2.5 py-1 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950"
          >
            Delete
          </button>
        </div>
      </div>
    );
  }

  const obj = variant.objects.find((o) => o.id === selectedObjectIds[0]);
  if (!obj) return null;
  const entry = OBJECT_LIBRARY[obj.typeId];
  const warnings = variant.warnings.filter((w) => w.objectIds.includes(obj.id));

  const field = (label: string, key: 'x' | 'y' | 'width' | 'height' | 'rotationDeg', step = 0.1) => (
    <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
      {label}
      <input
        type="number"
        step={step}
        value={Math.round(obj.transform[key] * 10) / 10}
        disabled={obj.locked}
        onChange={(e) => updateObjectTransform(obj.id, { [key]: Number(e.target.value) })}
        className="w-20 rounded border border-stone-300 px-1.5 py-0.5 text-right disabled:opacity-50 dark:border-stone-700 dark:bg-stone-900"
      />
    </label>
  );

  return (
    <div className="space-y-3 p-3 text-xs">
      <div>
        <h3 className="text-sm font-semibold text-stone-800 dark:text-stone-100">{obj.label}</h3>
        {entry && <p className="mt-0.5 text-[11px] text-stone-500 dark:text-stone-400">{entry.description}</p>}
        {obj.locked && <p className="mt-1 text-[11px] font-medium text-amber-700 dark:text-amber-500">Locked / as-built</p>}
      </div>

      <div className="space-y-1.5 rounded-md border border-stone-200 p-2 dark:border-stone-800">
        {field('X (m)', 'x')}
        {field('Y (m)', 'y')}
        {field('Width (m)', 'width')}
        {field('Height (m)', 'height')}
        {field('Rotation (°)', 'rotationDeg', 5)}
      </div>

      {obj.rationale && (
        <div className="rounded-md bg-stone-100 p-2 text-[11px] text-stone-600 dark:bg-stone-900 dark:text-stone-300">
          <span className="font-semibold">Why here: </span>
          {obj.rationale}
        </div>
      )}

      {warnings.length > 0 && (
        <div>
          <h4 className="mb-1 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">Warnings</h4>
          <ul className="space-y-1">
            {warnings.map((w) => (
              <li key={w.id} className="rounded border border-amber-300 bg-amber-50 px-2 py-1 text-[11px] text-amber-800 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-300">
                {w.message}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="flex gap-2 pt-1">
        <button
          onClick={() => toggleLock(obj.id)}
          className="rounded-md border border-stone-300 px-2.5 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
        >
          {obj.locked ? 'Unlock' : 'Lock'}
        </button>
        <button
          onClick={() => duplicateObjects([obj.id])}
          className="rounded-md border border-stone-300 px-2.5 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
        >
          Duplicate
        </button>
        <button
          onClick={() => deleteObjects([obj.id])}
          className="rounded-md border border-red-300 px-2.5 py-1 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950"
        >
          Delete
        </button>
      </div>
    </div>
  );
}
