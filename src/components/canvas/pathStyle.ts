import type { PathEntity } from '../../domain/types';

export interface PathStyle {
  stroke: string;
  strokeWidth: number;
  dasharray?: string;
  opacity: number;
}

// Paved driveways/entrances read as solid, wider, greyer; garden paths stay
// the lighter dashed-gravel treatment.
export function pathStyle(p: PathEntity): PathStyle {
  if (p.surfaceType === 'paved') {
    return { stroke: '#9c968a', strokeWidth: Math.min(p.widthM, 3), opacity: 0.75 };
  }
  return { stroke: '#c2b49a', strokeWidth: Math.min(0.6, p.widthM), dasharray: '0.5,0.7', opacity: 0.55 };
}
