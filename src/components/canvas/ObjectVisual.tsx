import type { PlanObject, ZoneCategory } from '../../domain/types';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import { CATEGORY_STYLES } from '../../domain/categories';
import { ObjectGlyph, lShapeVertices } from './objectGlyphs';

export interface ObjectVisualProps {
  obj: PlanObject;
  themeKey: 'light' | 'dark';
  showDesignDetail?: boolean;
  hasWarning?: boolean;
  isSelected?: boolean;
  textClassName?: string;
}

function lShapePoints(width: number, height: number): string {
  return lShapeVertices(width, height)
    .map((p) => p.join(','))
    .join(' ');
}

// Renders one object's fill shape + type-specific decorative glyph + label.
// Shared by the interactive canvas and the static export renderer so the two
// never visually drift apart.
export function ObjectVisual({ obj, themeKey, showDesignDetail, hasWarning, isSelected, textClassName }: ObjectVisualProps) {
  const entry = OBJECT_LIBRARY[obj.typeId];
  const style = CATEGORY_STYLES[obj.category as ZoneCategory];
  const fill = style?.[themeKey].fill ?? '#ddd';
  const stroke = hasWarning ? '#b3452e' : style?.[themeKey].stroke ?? '#888';
  const { width, height } = obj.transform;
  const shape = entry?.shape ?? 'rect';
  const strokeWidth = isSelected ? 0.3 : 0.15;
  const fillOpacity = obj.locked ? 0.5 : 0.85;
  const dash = obj.locked ? '0.4,0.3' : undefined;
  const fontSize = Math.min(1.6, Math.max(0.7, Math.min(width, height) / 4));

  return (
    <>
      {shape === 'circle' && (
        <circle
          r={Math.min(width, height) / 2}
          fill={fill}
          fillOpacity={fillOpacity}
          stroke={stroke}
          strokeWidth={strokeWidth}
          strokeDasharray={dash}
        />
      )}
      {shape === 'oval' && (
        <ellipse rx={width / 2} ry={height / 2} fill={fill} fillOpacity={fillOpacity} stroke={stroke} strokeWidth={strokeWidth} strokeDasharray={dash} />
      )}
      {shape === 'lshape' && (
        <polygon points={lShapePoints(width, height)} fill={fill} fillOpacity={fillOpacity} stroke={stroke} strokeWidth={strokeWidth} strokeDasharray={dash} />
      )}
      {shape === 'rect' && (
        <rect
          x={-width / 2}
          y={-height / 2}
          width={width}
          height={height}
          fill={fill}
          fillOpacity={fillOpacity}
          stroke={stroke}
          strokeWidth={strokeWidth}
          strokeDasharray={dash}
          rx={0.2}
        />
      )}

      {entry && <ObjectGlyph entry={entry} width={width} height={height} stroke={style?.[themeKey].stroke ?? '#888'} />}

      {showDesignDetail && shape === 'rect' && (
        <rect
          x={-width / 2 + 0.3}
          y={-height / 2 + 0.3}
          width={Math.max(0, width - 0.6)}
          height={Math.max(0, height - 0.6)}
          fill="none"
          stroke={style?.[themeKey].stroke ?? '#888'}
          strokeWidth={0.06}
          strokeDasharray="0.2,0.2"
        />
      )}

      <text
        textAnchor="middle"
        dominantBaseline="middle"
        fontSize={fontSize}
        fill="#1c1917"
        className={textClassName ?? 'select-none'}
        transform={`rotate(${-obj.transform.rotationDeg})`}
      >
        {obj.label}
      </text>

      {hasWarning && <circle cx={width / 2 - 0.5} cy={-height / 2 + 0.5} r={0.35} fill="#b3452e" />}
    </>
  );
}
