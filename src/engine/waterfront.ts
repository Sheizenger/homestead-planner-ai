import type { Plot, Zone } from '../domain/types';
import { polygonBounds, type Bounds } from './geometry';

// The waterfront strip is modelled as a slice of the plot itself (inset from
// one boundary edge by widthM) rather than land beyond the property line —
// this is how rural parcels with river/lake/pond frontage usually work, and
// it reuses all existing polygon/placement machinery for free.
export function computeWaterfrontBounds(plot: Plot): Bounds | null {
  const wf = plot.waterfront;
  if (!wf) return null;
  const b = polygonBounds(plot.boundary);
  const width = Math.max(0, Math.min(wf.widthM, wf.edge === 'north' || wf.edge === 'south' ? b.maxY - b.minY : b.maxX - b.minX));
  switch (wf.edge) {
    case 'north':
      return { minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.minY + width };
    case 'south':
      return { minX: b.minX, minY: b.maxY - width, maxX: b.maxX, maxY: b.maxY };
    case 'west':
      return { minX: b.minX, minY: b.minY, maxX: b.minX + width, maxY: b.maxY };
    case 'east':
      return { minX: b.maxX - width, minY: b.minY, maxX: b.maxX, maxY: b.maxY };
  }
}

export function computeWaterfrontZone(plot: Plot): Zone | null {
  const wf = plot.waterfront;
  const bounds = computeWaterfrontBounds(plot);
  if (!wf || !bounds) return null;
  return {
    id: 'zone-waterfront',
    category: 'water',
    boundary: [
      { x: bounds.minX, y: bounds.minY },
      { x: bounds.maxX, y: bounds.minY },
      { x: bounds.maxX, y: bounds.maxY },
      { x: bounds.minX, y: bounds.maxY },
    ],
    label: wf.type,
    metadata: { waterfrontType: wf.type },
    locked: true,
  };
}

// Rough planning thresholds for a small run-of-river or drop-based
// micro-hydro setup — not a substitute for a real hydrology assessment.
export const MIN_HYDRO_FLOW_MPS = 0.5;
export const MIN_HYDRO_DROP_M = 1;

export function isHydroFeasible(plot: Plot): boolean {
  const wf = plot.waterfront;
  if (!wf) return false;
  return (wf.flowSpeedMps ?? 0) >= MIN_HYDRO_FLOW_MPS || (wf.elevationDropM ?? 0) >= MIN_HYDRO_DROP_M;
}
