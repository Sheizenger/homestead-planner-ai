import { useState } from 'react';
import { useProjectStore } from '../../state/projectStore';
import { t } from '../../i18n/translations';
import { ObjectPropertiesPanel } from '../panels/ObjectPropertiesPanel';
import { WarningsList } from '../panels/WarningsList';
import { AnalyticsPanel } from '../panels/AnalyticsPanel';
import { QuickEditPanel } from '../panels/QuickEditPanel';

type Tab = 'properties' | 'warnings' | 'analytics' | 'edit';

const TAB_KEYS: Record<Tab, string> = {
  properties: 'tab.properties',
  warnings: 'tab.warnings',
  analytics: 'tab.analytics',
  edit: 'tab.edit',
};

export function RightPanel() {
  const locale = useProjectStore((s) => s.locale);
  const [tab, setTab] = useState<Tab>('properties');

  return (
    <div className="flex h-full flex-col">
      <div className="flex border-b border-stone-200 text-xs dark:border-stone-800">
        {(['properties', 'warnings', 'analytics', 'edit'] as Tab[]).map((tb) => (
          <button
            key={tb}
            onClick={() => setTab(tb)}
            className={`flex-1 py-2.5 font-medium transition-colors ${
              tab === tb
                ? 'border-b-2 border-emerald-700 text-emerald-800 dark:border-emerald-500 dark:text-emerald-400'
                : 'text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200'
            }`}
          >
            {t(locale, TAB_KEYS[tb])}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto">
        {tab === 'properties' && <ObjectPropertiesPanel />}
        {tab === 'warnings' && <WarningsList />}
        {tab === 'analytics' && <AnalyticsPanel />}
        {tab === 'edit' && <QuickEditPanel />}
      </div>
    </div>
  );
}
