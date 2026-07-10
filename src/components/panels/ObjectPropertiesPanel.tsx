import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import { t } from '../../i18n/translations';
import { objectLabel } from '../../i18n/labels';
import { translateRationale } from '../../i18n/rationale';
import { translateWarning } from '../../i18n/warnings';

export function ObjectPropertiesPanel() {
  const project = useProjectStore((s) => s.project);
  const locale = useProjectStore((s) => s.locale);
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);
  const updateObjectTransform = useProjectStore((s) => s.updateObjectTransform);
  const toggleLock = useProjectStore((s) => s.toggleLock);
  const deleteObjects = useProjectStore((s) => s.deleteObjects);
  const duplicateObjects = useProjectStore((s) => s.duplicateObjects);
  const variant = getActiveVariant(project);

  if (!variant || selectedObjectIds.length === 0) {
    return <p className="p-3 text-xs text-stone-500 dark:text-stone-400">{t(locale, 'props.selectPrompt')}</p>;
  }

  if (selectedObjectIds.length > 1) {
    const objs = variant.objects.filter((o) => selectedObjectIds.includes(o.id));
    return (
      <div className="space-y-3 p-3 text-xs">
        <p className="text-stone-600 dark:text-stone-300">{t(locale, 'props.multiSelected', { count: objs.length })}</p>
        <div className="flex gap-2">
          <button
            onClick={() => duplicateObjects(selectedObjectIds)}
            className="rounded-md border border-stone-300 px-2.5 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
          >
            {t(locale, 'props.duplicate')}
          </button>
          <button
            onClick={() => deleteObjects(selectedObjectIds)}
            className="rounded-md border border-red-300 px-2.5 py-1 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950"
          >
            {t(locale, 'props.delete')}
          </button>
        </div>
      </div>
    );
  }

  const obj = variant.objects.find((o) => o.id === selectedObjectIds[0]);
  if (!obj) return null;
  const entry = OBJECT_LIBRARY[obj.typeId];
  const warnings = variant.warnings.filter((w) => w.objectIds.includes(obj.id));
  const rationaleTokens = Array.isArray(obj.metadata.rationaleTokens) ? (obj.metadata.rationaleTokens as string[]) : undefined;

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
        <h3 className="text-sm font-semibold text-stone-800 dark:text-stone-100">{objectLabel(locale, obj.typeId)}</h3>
        {entry && <p className="mt-0.5 text-[11px] text-stone-500 dark:text-stone-400">{entry.description}</p>}
        {obj.locked && <p className="mt-1 text-[11px] font-medium text-amber-700 dark:text-amber-500">{t(locale, 'props.locked')}</p>}
      </div>

      <div className="space-y-1.5 rounded-md border border-stone-200 p-2 dark:border-stone-800">
        {field(t(locale, 'props.x'), 'x')}
        {field(t(locale, 'props.y'), 'y')}
        {field(t(locale, 'props.width'), 'width')}
        {field(t(locale, 'props.height'), 'height')}
        {field(t(locale, 'props.rotation'), 'rotationDeg', 5)}
      </div>

      {!obj.locked && rationaleTokens && (
        <div className="rounded-md bg-stone-100 p-2 text-[11px] text-stone-600 dark:bg-stone-900 dark:text-stone-300">
          <span className="font-semibold">{t(locale, 'props.whyHere')}</span>
          {translateRationale(locale, obj.typeId, rationaleTokens)}
        </div>
      )}

      {warnings.length > 0 && (
        <div>
          <h4 className="mb-1 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">{t(locale, 'props.warnings')}</h4>
          <ul className="space-y-1">
            {warnings.map((w) => (
              <li key={w.id} className="rounded border border-amber-300 bg-amber-50 px-2 py-1 text-[11px] text-amber-800 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-300">
                {translateWarning(locale, w)}
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
          {obj.locked ? t(locale, 'props.unlock') : t(locale, 'props.lock')}
        </button>
        <button
          onClick={() => duplicateObjects([obj.id])}
          className="rounded-md border border-stone-300 px-2.5 py-1 hover:bg-stone-100 dark:border-stone-700 dark:hover:bg-stone-800"
        >
          {t(locale, 'props.duplicate')}
        </button>
        <button
          onClick={() => deleteObjects([obj.id])}
          className="rounded-md border border-red-300 px-2.5 py-1 text-red-700 hover:bg-red-50 dark:border-red-900 dark:text-red-400 dark:hover:bg-red-950"
        >
          {t(locale, 'props.delete')}
        </button>
      </div>
    </div>
  );
}
