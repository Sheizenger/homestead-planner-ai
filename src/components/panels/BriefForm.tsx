import { useState } from 'react';
import { useProjectStore } from '../../state/projectStore';
import type { PlanningMode } from '../../domain/types';
import { parseFreeText } from '../../engine/textParser';

const CROP_OPTIONS = ['potato', 'grain', 'vegetable', 'berries', 'orchard', 'vineyard', 'greenhouse', 'hydroponic', 'raised-beds'];
const INFRA_OPTIONS = ['solar', 'well', 'septic', 'water-tank', 'generator', 'compost', 'cellar', 'woodshed', 'garage', 'barn'];
const MODE_OPTIONS: { value: PlanningMode; label: string }[] = [
  { value: 'minimum-maintenance', label: 'Minimum Maintenance' },
  { value: 'production-max', label: 'Maximum Productivity' },
  { value: 'beauty-balanced', label: 'Beauty + Function Balance' },
  { value: 'safety-first', label: 'Safety First' },
];

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border-b border-stone-200 py-4 dark:border-stone-800">
      <h3 className="mb-2 text-xs font-semibold tracking-wide text-stone-500 uppercase dark:text-stone-400">{title}</h3>
      {children}
    </div>
  );
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full border px-2.5 py-1 text-xs transition-colors ${
        active
          ? 'border-emerald-700 bg-emerald-700 text-white dark:border-emerald-600 dark:bg-emerald-600'
          : 'border-stone-300 text-stone-600 hover:border-stone-400 dark:border-stone-700 dark:text-stone-300'
      }`}
    >
      {children}
    </button>
  );
}

export function BriefForm() {
  const project = useProjectStore((s) => s.project);
  const updateFreeText = useProjectStore((s) => s.updateFreeText);
  const updateStructuredInputs = useProjectStore((s) => s.updateStructuredInputs);
  const generate = useProjectStore((s) => s.generate);
  const generating = useProjectStore((s) => s.generating);
  const [selectedMode, setSelectedMode] = useState<PlanningMode>('beauty-balanced');

  const inputs = project.brief.structuredInputs;
  const extraction = parseFreeText(project.brief.freeText);

  const toggleFromList = (list: string[], value: string) =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  return (
    <div className="flex h-full flex-col overflow-y-auto text-sm">
      <div className="border-b border-stone-200 p-4 dark:border-stone-800">
        <h2 className="text-sm font-semibold text-stone-800 dark:text-stone-100">Project Brief</h2>
        <p className="mt-1 text-xs text-stone-500 dark:text-stone-400">{project.name}</p>
      </div>

      <Section title="Free-text brief">
        <textarea
          value={project.brief.freeText}
          onChange={(e) => updateFreeText(e.target.value)}
          rows={5}
          placeholder="e.g. I want a family homestead for 3 people with potatoes, grain, orchard, berries, goats, greenhouse and solar…"
          className="w-full resize-none rounded-md border border-stone-300 bg-white p-2 text-xs text-stone-800 focus:border-emerald-600 focus:outline-none dark:border-stone-700 dark:bg-stone-900 dark:text-stone-100"
        />
        {extraction.unrecognizedTerms.length > 0 && (
          <p className="mt-1.5 text-[11px] text-amber-700 dark:text-amber-500">
            Not yet understood: {extraction.unrecognizedTerms.join(', ')}
          </p>
        )}
      </Section>

      <Section title="Household">
        <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
          Household size
          <input
            type="number"
            min={1}
            max={12}
            value={inputs.householdSize}
            onChange={(e) => updateStructuredInputs({ householdSize: Number(e.target.value) })}
            className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
          />
        </label>
      </Section>

      <Section title="Aesthetic preference">
        <input
          type="range"
          min={0}
          max={100}
          value={inputs.aestheticPreference}
          onChange={(e) => updateStructuredInputs({ aestheticPreference: Number(e.target.value) })}
          className="w-full accent-emerald-700"
        />
        <div className="flex justify-between text-[11px] text-stone-500 dark:text-stone-400">
          <span>Utilitarian</span>
          <span>Ornamental</span>
        </div>
      </Section>

      <Section title="Crops & growing">
        <div className="flex flex-wrap gap-1.5">
          {CROP_OPTIONS.map((c) => (
            <Chip
              key={c}
              active={inputs.crops.includes(c)}
              onClick={() => updateStructuredInputs({ crops: toggleFromList(inputs.crops, c) })}
            >
              {c.replace('-', ' ')}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title="Animals">
        <div className="space-y-2">
          {['goats', 'poultry'].map((type) => {
            const entry = inputs.animals.find((a) => a.type === type);
            return (
              <label key={type} className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
                <span className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={!!entry}
                    onChange={(e) =>
                      updateStructuredInputs({
                        animals: e.target.checked
                          ? [...inputs.animals, { type, count: type === 'goats' ? 4 : 6 }]
                          : inputs.animals.filter((a) => a.type !== type),
                      })
                    }
                  />
                  {type}
                </span>
                {entry && (
                  <input
                    type="number"
                    min={1}
                    value={entry.count}
                    onChange={(e) =>
                      updateStructuredInputs({
                        animals: inputs.animals.map((a) => (a.type === type ? { ...a, count: Number(e.target.value) } : a)),
                      })
                    }
                    className="w-14 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
                  />
                )}
              </label>
            );
          })}
        </div>
      </Section>

      <Section title="Infrastructure">
        <div className="flex flex-wrap gap-1.5">
          {INFRA_OPTIONS.map((infra) => (
            <Chip
              key={infra}
              active={inputs.infrastructure.includes(infra)}
              onClick={() => updateStructuredInputs({ infrastructure: toggleFromList(inputs.infrastructure, infra) })}
            >
              {infra.replace('-', ' ')}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title="Planning mode">
        <div className="space-y-1.5">
          {MODE_OPTIONS.map((m) => (
            <label key={m.value} className="flex items-center gap-2 text-xs text-stone-600 dark:text-stone-300">
              <input
                type="radio"
                name="mode"
                checked={selectedMode === m.value}
                onChange={() => setSelectedMode(m.value)}
              />
              {m.label}
            </label>
          ))}
        </div>
      </Section>

      <div className="p-4">
        <button
          type="button"
          onClick={() => generate(selectedMode)}
          disabled={generating}
          className="w-full rounded-md bg-emerald-700 py-2 text-sm font-medium text-white transition-colors hover:bg-emerald-800 disabled:opacity-50 dark:bg-emerald-600 dark:hover:bg-emerald-500"
        >
          {generating ? 'Generating…' : 'Generate Layout Variants'}
        </button>
      </div>
    </div>
  );
}
