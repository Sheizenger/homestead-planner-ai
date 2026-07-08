import { useMemo, useState } from 'react';
import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { computeCostEstimate, findRegion } from '../../engine/costs';
import { COST_REGIONS, CURRENCIES, CURRENCY_SYMBOLS, convertFromUsd, regionLabel, type CurrencyCode } from '../../domain/costData';

function formatMoney(usd: number, currency: CurrencyCode): string {
  const value = convertFromUsd(usd, currency);
  const decimals = currency === 'RUB' ? 0 : value >= 1000 ? 0 : 2;
  return `${CURRENCY_SYMBOLS[currency]}${value.toLocaleString(undefined, { maximumFractionDigits: decimals })}`;
}

export function CostModal() {
  const isOpen = useProjectStore((s) => s.isCostOpen);
  const setCostOpen = useProjectStore((s) => s.setCostOpen);
  const project = useProjectStore((s) => s.project);
  const costRegionId = useProjectStore((s) => s.costRegionId);
  const setCostRegion = useProjectStore((s) => s.setCostRegion);
  const customLandPriceUsd = useProjectStore((s) => s.customLandPriceUsd);
  const setCustomLandPrice = useProjectStore((s) => s.setCustomLandPrice);
  const [currency, setCurrency] = useState<CurrencyCode>('USD');
  const variant = getActiveVariant(project);

  const region = useMemo(() => {
    const base = findRegion(costRegionId);
    return base.id === 'custom' ? { ...base, landPricePerM2Usd: customLandPriceUsd } : base;
  }, [costRegionId, customLandPriceUsd]);

  const estimate = useMemo(() => (variant ? computeCostEstimate(variant, region) : null), [variant, region]);

  if (!isOpen || !variant || !estimate) return null;

  const countries = [...new Set(COST_REGIONS.filter((r) => r.id !== 'custom').map((r) => r.country))];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setCostOpen(false)}>
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-lg bg-white shadow-xl dark:bg-stone-900"
      >
        <div className="flex items-center justify-between border-b border-stone-200 px-4 py-3 dark:border-stone-800">
          <h2 className="text-sm font-semibold text-stone-800 dark:text-stone-100">Cost Estimate — {variant.strategyLabel}</h2>
          <button onClick={() => setCostOpen(false)} className="text-stone-500 hover:text-stone-800 dark:hover:text-stone-100">✕</button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 text-xs">
          <div className="mb-4 flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1 text-stone-600 dark:text-stone-300">
              Location
              <select
                value={costRegionId}
                onChange={(e) => setCostRegion(e.target.value)}
                className="rounded border border-stone-300 bg-white px-2 py-1 dark:border-stone-700 dark:bg-stone-800"
              >
                <option value="custom">Custom / other location</option>
                {countries.map((country) => (
                  <optgroup key={country} label={country}>
                    {COST_REGIONS.filter((r) => r.country === country).map((r) => (
                      <option key={r.id} value={r.id}>{r.region}</option>
                    ))}
                  </optgroup>
                ))}
              </select>
            </label>

            {costRegionId === 'custom' && (
              <label className="flex flex-col gap-1 text-stone-600 dark:text-stone-300">
                Land price (USD/m²)
                <input
                  type="number"
                  min={0}
                  step={0.1}
                  value={customLandPriceUsd}
                  onChange={(e) => setCustomLandPrice(Number(e.target.value))}
                  className="w-28 rounded border border-stone-300 px-2 py-1 dark:border-stone-700 dark:bg-stone-800"
                />
              </label>
            )}

            <div className="ml-auto flex gap-1 rounded-md border border-stone-300 p-0.5 dark:border-stone-700">
              {CURRENCIES.map((c) => (
                <button
                  key={c}
                  onClick={() => setCurrency(c)}
                  className={`rounded px-2.5 py-1 font-medium ${
                    currency === c ? 'bg-emerald-700 text-white dark:bg-emerald-600' : 'text-stone-600 dark:text-stone-300'
                  }`}
                >
                  {c}
                </button>
              ))}
            </div>
          </div>

          <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Land" usd={estimate.landCostUsd} />
            <Stat label="Construction" usd={estimate.constructionTotalUsd} />
            <Stat label="Total upfront" usd={estimate.totalUpfrontUsd} emphasize />
            <Stat label="Annual upkeep" usd={estimate.annualMaintenanceTotalUsd} />
          </div>

          <div className="overflow-hidden rounded-md border border-stone-200 dark:border-stone-800">
            <table className="w-full text-left">
              <thead className="bg-stone-100 text-[11px] uppercase tracking-wide text-stone-500 dark:bg-stone-800 dark:text-stone-400">
                <tr>
                  <th className="px-3 py-1.5 font-medium">Category</th>
                  <th className="px-3 py-1.5 text-right font-medium">Install ({currency})</th>
                  <th className="px-3 py-1.5 text-right font-medium">Annual ({currency})</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100 dark:divide-stone-800">
                <tr>
                  <td className="px-3 py-1.5 text-stone-700 dark:text-stone-200">Land ({estimate.landAreaM2.toLocaleString()} m²)</td>
                  <td className="px-3 py-1.5 text-right text-stone-700 dark:text-stone-200">{formatMoney(estimate.landCostUsd, currency)}</td>
                  <td className="px-3 py-1.5 text-right text-stone-400 dark:text-stone-500">—</td>
                </tr>
                {estimate.rows.map((row) => (
                  <tr key={row.label}>
                    <td className="px-3 py-1.5 text-stone-700 dark:text-stone-200">{row.label}</td>
                    <td className="px-3 py-1.5 text-right text-stone-700 dark:text-stone-200">{formatMoney(row.installUsd, currency)}</td>
                    <td className="px-3 py-1.5 text-right text-stone-700 dark:text-stone-200">{formatMoney(row.annualUsd, currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="mt-3 text-[11px] text-stone-500 dark:text-stone-400">
            Rough planning estimate for {regionLabel(region)} — land prices, labor costs, and exchange rates (fixed:
            1 USD ≈ {CURRENCY_SYMBOLS.EUR}{convertFromUsd(1, 'EUR').toFixed(2)} / {CURRENCY_SYMBOLS.RUB}{convertFromUsd(1, 'RUB').toFixed(0)}) are
            2025 market-report approximations, not a quote. Real costs vary significantly by exact parcel, materials, and
            contractor; taxes and permitting fees are not included. Locked/as-built objects are excluded from
            construction cost since they already exist.
          </p>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, usd, emphasize }: { label: string; usd: number; emphasize?: boolean }) {
  return (
    <div className={`rounded-md border px-3 py-2 ${emphasize ? 'border-emerald-600 bg-emerald-50 dark:bg-emerald-950' : 'border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900'}`}>
      <div className="text-[10px] text-stone-500 dark:text-stone-400">{label}</div>
      <div className="space-y-0.5">
        {CURRENCIES.map((c) => (
          <div key={c} className="text-sm font-semibold text-stone-800 dark:text-stone-100">
            {formatMoney(usd, c)}
          </div>
        ))}
      </div>
    </div>
  );
}
