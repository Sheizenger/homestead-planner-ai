import type { PlanObject, Season, ZoneCategory } from '../../domain/types';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import { CATEGORY_STYLES, TYPE_STYLE_OVERRIDE } from '../../domain/categories';
import { seasonalFillOverride } from '../../domain/seasons';
import type { Locale } from '../../i18n/translations';
import { objectLabel } from '../../i18n/labels';
import { ObjectGlyph, lShapeVertices } from './objectGlyphs';

export interface ObjectVisualProps {
  obj: PlanObject;
  themeKey: 'light' | 'dark';
  locale: Locale;
  showDesignDetail?: boolean;
  hasWarning?: boolean;
  isSelected?: boolean;
  textClassName?: string;
  season?: Season;
}

function lShapePoints(width: number, height: number): string {
  return lShapeVertices(width, height)
    .map((p) => p.join(','))
    .join(' ');
}

const MIN_LABEL_FONT = 0.55;
const MAX_LABEL_FONT = 1.6;
const CHAR_WIDTH_RATIO = 0.56; // rough average glyph width as a fraction of font size

// Font size that keeps the label's estimated width inside the shape, or null
// if even the smallest legible size wouldn't fit — callers then caption the
// label just outside the shape (or omit it) instead of letting it overflow
// straight through a small icon with center alignment, which reads as broken.
function fitLabelFontSize(label: string, width: number, height: number): number | null {
  const idealFont = Math.min(MAX_LABEL_FONT, Math.max(MIN_LABEL_FONT, Math.min(width, height) / 4));
  if (label.length === 0) return idealFont;
  const availableWidth = Math.max(0, width - 0.5);
  const widthFit = availableWidth / (label.length * CHAR_WIDTH_RATIO);
  const fitted = Math.min(idealFont, widthFit);
  return fitted >= MIN_LABEL_FONT ? fitted : null;
}

// Renders one object's fill shape + type-specific decorative glyph + label.
// Shared by the interactive canvas and the static export renderer so the two
// never visually drift apart.
export function ObjectVisual({ obj, themeKey, locale, showDesignDetail, hasWarning, isSelected, textClassName, season }: ObjectVisualProps) {
  const entry = OBJECT_LIBRARY[obj.typeId];
  const style = CATEGORY_STYLES[obj.category as ZoneCategory];
  const typeStyle = TYPE_STYLE_OVERRIDE[obj.typeId];
  const fill = seasonalFillOverride(obj.category as ZoneCategory, season) ?? typeStyle?.[themeKey].fill ?? style?.[themeKey].fill ?? '#ddd';
  const stroke = hasWarning ? '#b3452e' : typeStyle?.[themeKey].stroke ?? style?.[themeKey].stroke ?? '#888';
  const { width, height } = obj.transform;
  const shape = entry?.shape ?? 'rect';
  const strokeWidth = isSelected ? 0.3 : 0.15;
  const fillOpacity = obj.locked ? 0.5 : 0.85;
  const dash = obj.locked ? '0.4,0.3' : undefined;
  const label = objectLabel(locale, obj.typeId);
  const labelFont = fitLabelFontSize(label, width, height);
  // Roof-mounted equipment sits visually on top of the house's own fill, so
  // it gets an outline instead of a second opaque, category-colored block
  // covering part of the roof.
  const roofMounted = obj.metadata.roofMounted === true;

  if (roofMounted) {
    return (
      <>
        <rect
          x={-width / 2}
          y={-height / 2}
          width={width}
          height={height}
          fill="none"
          stroke={stroke}
          strokeWidth={0.1}
          strokeDasharray="0.3,0.2"
          rx={0.1}
        />
        {entry && <ObjectGlyph entry={entry} width={width} height={height} stroke={style?.[themeKey].stroke ?? '#888'} season={season} />}
        {labelFont !== null && (
          <text
            textAnchor="middle"
            dominantBaseline="middle"
            fontSize={labelFont}
            fill="#1c1917"
            className={textClassName ?? 'select-none'}
          >
            {label}
          </text>
        )}
        {hasWarning && <circle cx={width / 2 - 0.4} cy={-height / 2 + 0.4} r={0.3} fill="#b3452e" />}
      </>
    );
  }

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

      {entry && <ObjectGlyph entry={entry} width={width} height={height} stroke={typeStyle?.[themeKey].stroke ?? style?.[themeKey].stroke ?? '#888'} season={season} />}

      {showDesignDetail && shape === 'rect' && (
        <rect
          x={-width / 2 + 0.3}
          y={-height / 2 + 0.3}
          width={Math.max(0, width - 0.6)}
          height={Math.max(0, height - 0.6)}
          fill="none"
          stroke={typeStyle?.[themeKey].stroke ?? style?.[themeKey].stroke ?? '#888'}
          strokeWidth={0.06}
          strokeDasharray="0.2,0.2"
        />
      )}

      <text
        textAnchor="middle"
        dominantBaseline={labelFont !== null ? 'middle' : 'hanging'}
        y={labelFont !== null ? 0 : (obj.transform.rotationDeg % 180 !== 0 ? width : height) / 2 + 0.5}
        fontSize={labelFont ?? MIN_LABEL_FONT}
        fill="#1c1917"
        className={textClassName ?? 'select-none'}
        transform={`rotate(${-obj.transform.rotationDeg})`}
      >
        {label}
      </text>

      {hasWarning && <circle cx={width / 2 - 0.5} cy={-height / 2 + 0.5} r={0.35} fill="#b3452e" />}
    </>
  );
}
