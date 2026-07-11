import type { PathEntity } from '../../domain/types';

export interface PathStyle {
  stroke: string;
  strokeWidth: number;
  dasharray?: string;
  opacity: number;
}

// Paved driveways/entrances read as solid, wider, greyer; garden paths stay
// the lighter dashed-gravel treatment. The driveway (category 'service') is
// darker asphalt rather than the lighter paved-walkway grey, so it reads as
// a real vehicle road leading somewhere (a garage), not just a wide walkway.
export function pathStyle(p: PathEntity): PathStyle {
  if (p.surfaceType === 'paved') {
    if (p.category === 'service') {
      return { stroke: '#6b6560', strokeWidth: Math.min(p.widthM, 3), opacity: 0.85 };
    }
    return { stroke: '#9c968a', strokeWidth: Math.min(p.widthM, 3), opacity: 0.75 };
  }
  return { stroke: '#c2b49a', strokeWidth: Math.min(0.6, p.widthM), dasharray: '0.5,0.7', opacity: 0.55 };
}
