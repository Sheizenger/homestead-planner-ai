import { useState } from 'react';
import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import { parseEditCommand, resizeTransform, findRepositionTarget } from '../../engine/editCommands';
import { objectLabel } from '../../i18n/labels';
import { t } from '../../i18n/translations';

const EXAMPLES = [
  'move the greenhouse near the well',
  'move the goat paddock away from the house',
  'make the garage bigger',
  'shrink the patio',
  'delete the compost yard',
  'duplicate the raised beds',
  'rotate the barn',
];

export function QuickEditPanel() {
  const locale = useProjectStore((s) => s.locale);
  const project = useProjectStore((s) => s.project);
  const variant = getActiveVariant(project);
  const updateObjectTransform = useProjectStore((s) => s.updateObjectTransform);
  const deleteObjects = useProjectStore((s) => s.deleteObjects);
  const duplicateObjects = useProjectStore((s) => s.duplicateObjects);
  const toggleLock = useProjectStore((s) => s.toggleLock);
  const select = useProjectStore((s) => s.select);

  const [text, setText] = useState('');
  const [feedback, setFeedback] = useState<{ ok: boolean; message: string } | null>(null);

  if (!variant) return null;

  const apply = () => {
    const parsed = parseEditCommand(text, variant);
    if (!parsed) {
      setFeedback({ ok: false, message: t(locale, 'quickEdit.notUnderstood') });
      return;
    }
    const subjects = variant.objects.filter((o) => o.typeId === parsed.subjectTypeId && !o.locked);
    if (subjects.length === 0) {
      setFeedback({ ok: false, message: t(locale, 'quickEdit.noMatch') });
      return;
    }

    const subjectLabel = objectLabel(locale, parsed.subjectTypeId);
    let touched = 0;

    switch (parsed.verb) {
      case 'delete':
        deleteObjects(subjects.map((o) => o.id));
        touched = subjects.length;
        break;
      case 'duplicate':
        duplicateObjects(subjects.map((o) => o.id));
        touched = subjects.length;
        break;
      case 'rotate':
        for (const o of subjects) updateObjectTransform(o.id, { rotationDeg: (o.transform.rotationDeg + 90) % 360 });
        touched = subjects.length;
        break;
      case 'lock':
        for (const o of subjects) if (!o.locked) toggleLock(o.id);
        touched = subjects.length;
        break;
      case 'unlock':
        for (const o of subjects) if (o.locked) toggleLock(o.id);
        touched = subjects.length;
        break;
      case 'enlarge':
      case 'shrink': {
        for (const o of subjects) {
          const entry = OBJECT_LIBRARY[o.typeId];
          if (!entry) continue;
          const size = resizeTransform(entry, o.transform, parsed.verb === 'enlarge');
          updateObjectTransform(o.id, size);
        }
        touched = subjects.length;
        break;
      }
      case 'move-near':
      case 'move-away': {
        const reference = variant.objects.find((o) => o.typeId === parsed.referenceTypeId);
        if (!reference) {
          setFeedback({ ok: false, message: t(locale, 'quickEdit.noMatch') });
          return;
        }
        for (const o of subjects) {
          const target = findRepositionTarget(variant, project.plot, o, reference, parsed.verb === 'move-near' ? 'near' : 'away');
          if (target) {
            updateObjectTransform(o.id, target);
            touched += 1;
          }
        }
        if (touched === 0) {
          setFeedback({ ok: false, message: t(locale, 'quickEdit.noRoom') });
          return;
        }
        break;
      }
    }

    select(subjects.map((o) => o.id));
    setFeedback({ ok: true, message: t(locale, 'quickEdit.applied', { subject: subjectLabel, count: touched }) });
    setText('');
  };

  return (
    <div className="flex h-full flex-col p-3 text-xs">
      <p className="mb-2 text-stone-500 dark:text-stone-400">{t(locale, 'quickEdit.hint')}</p>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            apply();
          }
        }}
        rows={2}
        placeholder={t(locale, 'quickEdit.placeholder')}
        className="w-full resize-none rounded-md border border-stone-300 bg-white p-2 text-xs text-stone-800 focus:border-emerald-600 focus:outline-none dark:border-stone-700 dark:bg-stone-900 dark:text-stone-100"
      />
      <button
        onClick={apply}
        disabled={!text.trim()}
        className="mt-2 self-start rounded-md bg-emerald-700 px-3 py-1.5 font-medium text-white hover:bg-emerald-800 disabled:opacity-40 dark:bg-emerald-600 dark:hover:bg-emerald-500"
      >
        {t(locale, 'quickEdit.apply')}
      </button>

      {feedback && (
        <p className={`mt-2 text-[11px] ${feedback.ok ? 'text-emerald-700 dark:text-emerald-400' : 'text-amber-700 dark:text-amber-500'}`}>
          {feedback.message}
        </p>
      )}

      <div className="mt-4">
        <div className="mb-1.5 text-[11px] font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">
          {t(locale, 'quickEdit.examplesTitle')}
        </div>
        <ul className="space-y-1">
          {EXAMPLES.map((ex) => (
            <li key={ex}>
              <button
                onClick={() => setText(ex)}
                className="text-left text-stone-500 hover:text-emerald-700 dark:text-stone-400 dark:hover:text-emerald-400"
              >
                “{ex}”
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
