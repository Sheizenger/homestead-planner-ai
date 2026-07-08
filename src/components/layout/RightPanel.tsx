import { useState } from 'react';
import { ObjectPropertiesPanel } from '../panels/ObjectPropertiesPanel';
import { WarningsList } from '../panels/WarningsList';
import { AnalyticsPanel } from '../panels/AnalyticsPanel';

type Tab = 'properties' | 'warnings' | 'analytics';

export function RightPanel() {
  const [tab, setTab] = useState<Tab>('properties');

  return (
    <div className="flex h-full flex-col">
      <div className="flex border-b border-stone-200 text-xs dark:border-stone-800">
        {(['properties', 'warnings', 'analytics'] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`flex-1 py-2.5 font-medium capitalize transition-colors ${
              tab === t
                ? 'border-b-2 border-emerald-700 text-emerald-800 dark:border-emerald-500 dark:text-emerald-400'
                : 'text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200'
            }`}
          >
            {t}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto">
        {tab === 'properties' && <ObjectPropertiesPanel />}
        {tab === 'warnings' && <WarningsList />}
        {tab === 'analytics' && <AnalyticsPanel />}
      </div>
    </div>
  );
}
