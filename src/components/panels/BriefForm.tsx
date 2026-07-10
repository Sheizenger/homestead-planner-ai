import { useState } from 'react';
import { useProjectStore } from '../../state/projectStore';
import type { ClimateZone, PlanningMode, WaterfrontEdge, WaterfrontType } from '../../domain/types';
import { parseFreeText } from '../../engine/textParser';
import { polygonBounds } from '../../engine/geometry';
import { RECOMMENDED_M2_PER_PERSON } from '../../engine/warnings';
import { t } from '../../i18n/translations';

const CROP_OPTIONS = ['potato', 'grain', 'vegetable', 'berries', 'orchard', 'vineyard', 'greenhouse', 'hydroponic', 'raised-beds'];
const INFRA_OPTIONS = [
  'solar', 'well', 'septic', 'water-tank', 'generator', 'compost', 'cellar', 'woodshed', 'garage', 'barn',
  'pool', 'gazebo', 'apiary', 'banya', 'smokehouse', 'workshop', 'rainwater-cistern',
];
// Only offered once a waterfront is configured — a dock or turbine needs
// somewhere to actually go.
const WATERFRONT_INFRA_OPTIONS = ['dock', 'micro-hydro'];
const ANIMAL_OPTIONS = ['goats', 'poultry'];
const WATERFRONT_TYPE_OPTIONS: { value: WaterfrontType; key: string }[] = [
  { value: 'river', key: 'waterfront.river' },
  { value: 'lake', key: 'waterfront.lake' },
  { value: 'pond', key: 'waterfront.pond' },
];
const WATERFRONT_EDGE_OPTIONS: { value: WaterfrontEdge; key: string }[] = [
  { value: 'north', key: 'edge.north' },
  { value: 'south', key: 'edge.south' },
  { value: 'east', key: 'edge.east' },
  { value: 'west', key: 'edge.west' },
];
const MODE_OPTIONS: { value: PlanningMode; key: string }[] = [
  { value: 'minimum-maintenance', key: 'planningMode.minimum-maintenance' },
  { value: 'production-max', key: 'planningMode.production-max' },
  { value: 'beauty-balanced', key: 'planningMode.beauty-balanced' },
  { value: 'safety-first', key: 'planningMode.safety-first' },
];
const HOUSE_SIZE_OPTIONS: { value: 'small' | 'medium' | 'large'; key: string }[] = [
  { value: 'small', key: 'houseSize.small' },
  { value: 'medium', key: 'houseSize.medium' },
  { value: 'large', key: 'houseSize.large' },
];
const HOUSE_SHAPE_OPTIONS: { value: 'rect' | 'lshape'; key: string }[] = [
  { value: 'rect', key: 'houseShape.rect' },
  { value: 'lshape', key: 'houseShape.lshape' },
];
const CLIMATE_OPTIONS: { value: ClimateZone; key: string }[] = [
  { value: 'temperate', key: 'climateZone.temperate' },
  { value: 'continental', key: 'climateZone.continental' },
  { value: 'mediterranean', key: 'climateZone.mediterranean' },
  { value: 'subtropical', key: 'climateZone.subtropical' },
  { value: 'arid', key: 'climateZone.arid' },
  { value: 'cold', key: 'climateZone.cold' },
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
  const locale = useProjectStore((s) => s.locale);
  const updateFreeText = useProjectStore((s) => s.updateFreeText);
  const updateStructuredInputs = useProjectStore((s) => s.updateStructuredInputs);
  const updatePlotSize = useProjectStore((s) => s.updatePlotSize);
  const updateWaterfront = useProjectStore((s) => s.updateWaterfront);
  const generate = useProjectStore((s) => s.generate);
  const generating = useProjectStore((s) => s.generating);
  const [selectedMode, setSelectedMode] = useState<PlanningMode>('beauty-balanced');

  const inputs = project.brief.structuredInputs;
  const waterfront = project.plot.waterfront;
  const extraction = parseFreeText(project.brief.freeText);
  const bounds = polygonBounds(project.plot.boundary);
  const plotWidth = Math.round(bounds.maxX - bounds.minX);
  const plotHeight = Math.round(bounds.maxY - bounds.minY);
  const plotAreaM2 = plotWidth * plotHeight;
  const recommendedM2 = inputs.householdSize * RECOMMENDED_M2_PER_PERSON;
  const shortOfNorm = plotAreaM2 < recommendedM2;
  const infraOptions = waterfront ? [...INFRA_OPTIONS, ...WATERFRONT_INFRA_OPTIONS] : INFRA_OPTIONS;

  const toggleFromList = (list: string[], value: string) =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  return (
    <div className="flex h-full flex-col overflow-y-auto text-sm">
      <div className="border-b border-stone-200 p-4 dark:border-stone-800">
        <h2 className="text-sm font-semibold text-stone-800 dark:text-stone-100">{t(locale, 'brief.title')}</h2>
        <p className="mt-1 text-xs text-stone-500 dark:text-stone-400">{project.name}</p>
      </div>

      <Section title={t(locale, 'brief.freeText')}>
        <textarea
          value={project.brief.freeText}
          onChange={(e) => updateFreeText(e.target.value)}
          rows={5}
          placeholder={t(locale, 'brief.freeTextPlaceholder')}
          className="w-full resize-none rounded-md border border-stone-300 bg-white p-2 text-xs text-stone-800 focus:border-emerald-600 focus:outline-none dark:border-stone-700 dark:bg-stone-900 dark:text-stone-100"
        />
        {extraction.unrecognizedTerms.length > 0 && (
          <p className="mt-1.5 text-[11px] text-amber-700 dark:text-amber-500">
            {t(locale, 'brief.notUnderstood', { terms: extraction.unrecognizedTerms.join(', ') })}
          </p>
        )}
      </Section>

      <Section title={t(locale, 'brief.household')}>
        <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
          {t(locale, 'brief.householdSize')}
          <input
            type="number"
            min={1}
            max={12}
            value={inputs.householdSize}
            onChange={(e) => updateStructuredInputs({ householdSize: Number(e.target.value) })}
            className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
          />
        </label>
        <p className={`mt-1.5 text-[11px] ${shortOfNorm ? 'text-amber-700 dark:text-amber-500' : 'text-stone-500 dark:text-stone-400'}`}>
          {shortOfNorm
            ? t(locale, 'brief.householdShort', { household: inputs.householdSize, recommended: recommendedM2.toLocaleString(), perPerson: RECOMMENDED_M2_PER_PERSON, area: plotAreaM2.toLocaleString() })
            : t(locale, 'brief.householdGuideline', { perPerson: RECOMMENDED_M2_PER_PERSON, recommended: recommendedM2.toLocaleString(), household: inputs.householdSize, area: plotAreaM2.toLocaleString() })}
        </p>
      </Section>

      <Section title={t(locale, 'brief.climateZone')}>
        <div className="flex flex-wrap gap-1.5">
          {CLIMATE_OPTIONS.map((o) => (
            <Chip
              key={o.value}
              active={inputs.climateZone === o.value}
              onClick={() => updateStructuredInputs({ climateZone: o.value })}
            >
              {t(locale, o.key)}
            </Chip>
          ))}
        </div>
        <p className="mt-1.5 text-[11px] text-stone-500 dark:text-stone-400">{t(locale, 'brief.climateHint')}</p>
      </Section>

      <Section title={t(locale, 'brief.plotSize')}>
        <div className="flex items-center gap-2 text-xs text-stone-600 dark:text-stone-300">
          <label className="flex items-center gap-1.5">
            {t(locale, 'brief.width')}
            <input
              type="number"
              min={10}
              step={1}
              value={plotWidth}
              onChange={(e) => updatePlotSize(Number(e.target.value), plotHeight)}
              className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
            />
            m
          </label>
          <label className="flex items-center gap-1.5">
            {t(locale, 'brief.depth')}
            <input
              type="number"
              min={10}
              step={1}
              value={plotHeight}
              onChange={(e) => updatePlotSize(plotWidth, Number(e.target.value))}
              className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
            />
            m
          </label>
        </div>
        <p className="mt-1.5 text-[11px] text-stone-500 dark:text-stone-400">
          {t(locale, 'brief.plotAreaSummary', { area: plotAreaM2.toLocaleString(), sotok: (plotAreaM2 / 100).toFixed(1) })}
        </p>
      </Section>

      <Section title={t(locale, 'brief.waterfront')}>
        <div className="flex flex-wrap gap-1.5">
          <Chip active={!waterfront} onClick={() => updateWaterfront(null)}>
            {t(locale, 'waterfront.none')}
          </Chip>
          {WATERFRONT_TYPE_OPTIONS.map((o) => (
            <Chip
              key={o.value}
              active={waterfront?.type === o.value}
              onClick={() =>
                updateWaterfront({
                  type: o.value,
                  edge: waterfront?.edge ?? 'west',
                  widthM: waterfront?.widthM ?? (o.value === 'pond' ? 6 : 10),
                  flowSpeedMps: waterfront?.flowSpeedMps ?? (o.value === 'river' ? 0.8 : undefined),
                  elevationDropM: waterfront?.elevationDropM ?? 1.5,
                })
              }
            >
              {t(locale, o.key)}
            </Chip>
          ))}
        </div>

        {waterfront && (
          <div className="mt-2 space-y-2">
            <div className="flex flex-wrap gap-1.5">
              {WATERFRONT_EDGE_OPTIONS.map((o) => (
                <Chip key={o.value} active={waterfront.edge === o.value} onClick={() => updateWaterfront({ ...waterfront, edge: o.value })}>
                  {t(locale, o.key)}
                </Chip>
              ))}
            </div>
            <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
              {t(locale, 'brief.waterfrontWidth')}
              <input
                type="number"
                min={2}
                step={1}
                value={waterfront.widthM}
                onChange={(e) => updateWaterfront({ ...waterfront, widthM: Number(e.target.value) })}
                className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
              />
            </label>
            {waterfront.type === 'river' && (
              <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
                {t(locale, 'brief.flowSpeed')}
                <input
                  type="number"
                  min={0}
                  step={0.1}
                  value={waterfront.flowSpeedMps ?? 0}
                  onChange={(e) => updateWaterfront({ ...waterfront, flowSpeedMps: Number(e.target.value) })}
                  className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
                />
              </label>
            )}
            {waterfront.type !== 'pond' && (
              <label className="flex items-center justify-between text-xs text-stone-600 dark:text-stone-300">
                {t(locale, 'brief.elevationDrop')}
                <input
                  type="number"
                  min={0}
                  step={0.1}
                  value={waterfront.elevationDropM ?? 0}
                  onChange={(e) => updateWaterfront({ ...waterfront, elevationDropM: Number(e.target.value) })}
                  className="w-16 rounded border border-stone-300 px-1.5 py-0.5 text-right dark:border-stone-700 dark:bg-stone-900"
                />
              </label>
            )}
            <p className="text-[11px] text-stone-500 dark:text-stone-400">{t(locale, 'brief.waterfrontHint')}</p>
          </div>
        )}
      </Section>

      <Section title={t(locale, 'brief.house')}>
        <div className="mb-2 flex flex-wrap gap-1.5">
          {HOUSE_SIZE_OPTIONS.map((o) => (
            <Chip
              key={o.value}
              active={inputs.houseSizePreset === o.value}
              onClick={() => updateStructuredInputs({ houseSizePreset: o.value })}
            >
              {t(locale, o.key)}
            </Chip>
          ))}
        </div>
        <div className="flex flex-wrap gap-1.5">
          {HOUSE_SHAPE_OPTIONS.map((o) => (
            <Chip
              key={o.value}
              active={inputs.houseShape === o.value}
              onClick={() => updateStructuredInputs({ houseShape: o.value })}
            >
              {t(locale, o.key)}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title={t(locale, 'brief.aesthetic')}>
        <input
          type="range"
          min={0}
          max={100}
          value={inputs.aestheticPreference}
          onChange={(e) => updateStructuredInputs({ aestheticPreference: Number(e.target.value) })}
          className="w-full accent-emerald-700"
        />
        <div className="flex justify-between text-[11px] text-stone-500 dark:text-stone-400">
          <span>{t(locale, 'brief.utilitarian')}</span>
          <span>{t(locale, 'brief.ornamental')}</span>
        </div>
      </Section>

      <Section title={t(locale, 'brief.crops')}>
        <div className="flex flex-wrap gap-1.5">
          {CROP_OPTIONS.map((c) => (
            <Chip
              key={c}
              active={inputs.crops.includes(c)}
              onClick={() => updateStructuredInputs({ crops: toggleFromList(inputs.crops, c) })}
            >
              {t(locale, `crop.${c}`)}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title={t(locale, 'brief.animals')}>
        <div className="space-y-2">
          {ANIMAL_OPTIONS.map((type) => {
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
                  {t(locale, `animal.${type}`)}
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

      <Section title={t(locale, 'brief.infrastructure')}>
        <div className="flex flex-wrap gap-1.5">
          {infraOptions.map((infra) => (
            <Chip
              key={infra}
              active={inputs.infrastructure.includes(infra)}
              onClick={() => updateStructuredInputs({ infrastructure: toggleFromList(inputs.infrastructure, infra) })}
            >
              {t(locale, `infra.${infra}`)}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title={t(locale, 'brief.planningMode')}>
        <div className="space-y-1.5">
          {MODE_OPTIONS.map((m) => (
            <label key={m.value} className="flex items-center gap-2 text-xs text-stone-600 dark:text-stone-300">
              <input
                type="radio"
                name="mode"
                checked={selectedMode === m.value}
                onChange={() => setSelectedMode(m.value)}
              />
              {t(locale, m.key)}
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
          {generating ? t(locale, 'brief.generating') : t(locale, 'brief.generate')}
        </button>
      </div>
    </div>
  );
}
