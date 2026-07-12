import { useCallback, useEffect, useMemo, useRef, useState, type ReactElement } from 'react';
import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { CATEGORY_STYLES, ZONE_CATEGORY_ORDER } from '../../domain/categories';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import type { LayoutVariant, PlanObject, Point, Transform, ZoneCategory } from '../../domain/types';
import { polygonBounds, rectCorners, resizeFromCorner } from '../../engine/geometry';
import { t, type Locale } from '../../i18n/translations';
import { categoryLabel } from '../../i18n/labels';
import { translateRationale } from '../../i18n/rationale';
import { ObjectVisual } from './ObjectVisual';
import { WaterfrontZone } from './WaterfrontZone';
import { ContourLines } from './ContourLines';
import { GateGlyph } from './GateGlyph';
import { pathStyle } from './pathStyle';

const PX_PER_METER = 12;
const PADDING_M = 6;

type DragMode =
  | { kind: 'move'; startPointer: Point; startTransforms: Record<string, Transform> }
  | { kind: 'resize'; objectId: string; cornerIndex: number; fixedCorner: Point; cornerSign: Point; rotationDeg: number }
  | { kind: 'rotate'; objectId: string; center: Point }
  | { kind: 'marquee'; startPointer: Point; currentPointer: Point }
  | { kind: 'plotVertex'; index: number };

const CORNER_SIGNS: Point[] = [
  { x: -1, y: -1 },
  { x: 1, y: -1 },
  { x: 1, y: 1 },
  { x: -1, y: 1 },
];

export function PlanCanvas() {
  const project = useProjectStore((s) => s.project);
  const variant = getActiveVariant(project);
  const theme = useProjectStore((s) => s.theme);
  const themeKey = theme === 'dark' ? 'dark' : 'light';
  const locale = useProjectStore((s) => s.locale);
  const visualizationMode = useProjectStore((s) => s.visualizationMode);
  const season = useProjectStore((s) => s.season);
  const showLegend = useProjectStore((s) => s.showLegend);
  const layerVisibility = useProjectStore((s) => s.layerVisibility);
  const snapToGrid = useProjectStore((s) => s.snapToGrid);
  const gridSize = useProjectStore((s) => s.gridSize);
  const zoom = useProjectStore((s) => s.zoom);
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);
  const select = useProjectStore((s) => s.select);
  const moveObjects = useProjectStore((s) => s.moveObjects);
  const editingPlotShape = useProjectStore((s) => s.editingPlotShape);
  const updatePlotBoundary = useProjectStore((s) => s.updatePlotBoundary);

  const svgRef = useRef<SVGSVGElement>(null);
  const [drag, setDrag] = useState<DragMode | null>(null);
  const [liveTransforms, setLiveTransforms] = useState<Record<string, Transform>>({});
  const [liveBoundary, setLiveBoundary] = useState<Point[] | null>(null);

  const bounds = useMemo(() => polygonBounds(project.plot.boundary), [project.plot.boundary]);
  const worldW = bounds.maxX - bounds.minX + PADDING_M * 2;
  const worldH = bounds.maxY - bounds.minY + PADDING_M * 2;
  const viewBox = `${bounds.minX - PADDING_M} ${bounds.minY - PADDING_M} ${worldW} ${worldH}`;

  const snap = useCallback(
    (v: number) => (snapToGrid ? Math.round(v / gridSize) * gridSize : v),
    [snapToGrid, gridSize],
  );

  const toWorld = useCallback((clientX: number, clientY: number): Point => {
    const svg = svgRef.current;
    if (!svg) return { x: 0, y: 0 };
    const rect = svg.getBoundingClientRect();
    const scaleX = worldW / rect.width;
    const scaleY = worldH / rect.height;
    return {
      x: bounds.minX - PADDING_M + (clientX - rect.left) * scaleX,
      y: bounds.minY - PADDING_M + (clientY - rect.top) * scaleY,
    };
  }, [bounds, worldW, worldH]);

  const objects = variant ? variant.objects.map((o) => (liveTransforms[o.id] ? { ...o, transform: liveTransforms[o.id] } : o)) : [];

  // Physical utility hookups (power cable / water pipe runs). Positions are
  // resolved live from `objects` (not stored on the node) so a line stays
  // attached to its object while it's being dragged, instead of freezing at
  // wherever it was when the plan was generated.
  const utilityLines = variant
    ? variant.utilityNodes.flatMap((n) => {
        const from = objects.find((o) => o.id === n.objectId);
        if (!from) return [];
        return n.connections.flatMap((targetId) => {
          const target = variant.utilityNodes.find((t) => t.id === targetId);
          const to = target && objects.find((o) => o.id === target.objectId);
          if (!to) return [];
          return [{ id: `${n.id}-${targetId}`, kind: n.kind, x1: from.transform.x, y1: from.transform.y, x2: to.transform.x, y2: to.transform.y }];
        });
      })
    : [];

  const handleObjectPointerDown = (e: React.PointerEvent, obj: PlanObject) => {
    e.stopPropagation();
    if (!variant) return;
    if (obj.locked) {
      select([obj.id]);
      return;
    }
    let nextSelection: string[];
    if (e.shiftKey) {
      nextSelection = selectedObjectIds.includes(obj.id)
        ? selectedObjectIds.filter((id) => id !== obj.id)
        : [...selectedObjectIds, obj.id];
    } else {
      nextSelection = selectedObjectIds.includes(obj.id) ? selectedObjectIds : [obj.id];
    }
    select(nextSelection);
    const startTransforms: Record<string, Transform> = {};
    for (const o of variant.objects) {
      if (nextSelection.includes(o.id)) startTransforms[o.id] = o.transform;
    }
    setDrag({ kind: 'move', startPointer: toWorld(e.clientX, e.clientY), startTransforms });
  };

  const handleResizeStart = (e: React.PointerEvent, obj: PlanObject, cornerIndex: number) => {
    e.stopPropagation();
    const corners = rectCorners(obj.transform);
    const oppositeIndex = (cornerIndex + 2) % 4;
    setDrag({
      kind: 'resize',
      objectId: obj.id,
      cornerIndex,
      fixedCorner: corners[oppositeIndex],
      cornerSign: CORNER_SIGNS[cornerIndex],
      rotationDeg: obj.transform.rotationDeg,
    });
  };

  const handleRotateStart = (e: React.PointerEvent, obj: PlanObject) => {
    e.stopPropagation();
    setDrag({ kind: 'rotate', objectId: obj.id, center: { x: obj.transform.x, y: obj.transform.y } });
  };

  const handleBackgroundPointerDown = (e: React.PointerEvent) => {
    if (editingPlotShape) return;
    const p = toWorld(e.clientX, e.clientY);
    setDrag({ kind: 'marquee', startPointer: p, currentPointer: p });
    if (!e.shiftKey) select([]);
  };

  const handlePlotVertexPointerDown = (e: React.PointerEvent, index: number) => {
    e.stopPropagation();
    setLiveBoundary([...project.plot.boundary]);
    setDrag({ kind: 'plotVertex', index });
  };

  const handlePlotVertexDoubleClick = (e: React.MouseEvent, index: number) => {
    e.stopPropagation();
    if (project.plot.boundary.length <= 3) return;
    updatePlotBoundary(project.plot.boundary.filter((_, i) => i !== index));
  };

  const handlePlotEdgeInsert = (e: React.PointerEvent, afterIndex: number) => {
    e.stopPropagation();
    const boundary = project.plot.boundary;
    const a = boundary[afterIndex];
    const b = boundary[(afterIndex + 1) % boundary.length];
    const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    updatePlotBoundary([...boundary.slice(0, afterIndex + 1), mid, ...boundary.slice(afterIndex + 1)]);
  };

  useEffect(() => {
    if (!drag || (!variant && drag.kind !== 'plotVertex')) return;

    const handleMove = (e: PointerEvent) => {
      const p = toWorld(e.clientX, e.clientY);
      if (drag.kind === 'plotVertex') {
        setLiveBoundary((prev) => {
          const base = prev ?? project.plot.boundary;
          return base.map((pt, i) => (i === drag.index ? { x: snap(p.x), y: snap(p.y) } : pt));
        });
      } else if (drag.kind === 'move') {
        const dx = snap(p.x - drag.startPointer.x);
        const dy = snap(p.y - drag.startPointer.y);
        const next: Record<string, Transform> = {};
        for (const [id, t] of Object.entries(drag.startTransforms)) {
          next[id] = { ...t, x: t.x + dx, y: t.y + dy };
        }
        setLiveTransforms(next);
      } else if (drag.kind === 'resize' && variant) {
        const entry = OBJECT_LIBRARY[variant.objects.find((o) => o.id === drag.objectId)?.typeId ?? ''];
        const t = resizeFromCorner(
          drag.fixedCorner,
          drag.cornerSign,
          drag.rotationDeg,
          p,
          entry?.minWidth ?? 1,
          entry?.minHeight ?? 1,
        );
        setLiveTransforms({ [drag.objectId]: { x: snap(t.x), y: snap(t.y), width: snap(t.width), height: snap(t.height), rotationDeg: t.rotationDeg } });
      } else if (drag.kind === 'rotate' && variant) {
        const angle = (Math.atan2(p.y - drag.center.y, p.x - drag.center.x) * 180) / Math.PI + 90;
        const obj = variant.objects.find((o) => o.id === drag.objectId);
        if (obj) setLiveTransforms({ [drag.objectId]: { ...obj.transform, rotationDeg: Math.round(angle / 5) * 5 } });
      } else if (drag.kind === 'marquee') {
        setDrag({ ...drag, currentPointer: p });
      }
    };

    const handleUp = () => {
      if (drag.kind === 'plotVertex') {
        if (liveBoundary) updatePlotBoundary(liveBoundary);
        setLiveBoundary(null);
      } else if (drag.kind === 'move' || drag.kind === 'resize' || drag.kind === 'rotate') {
        const updates = Object.entries(liveTransforms).map(([id, transform]) => ({ id, transform }));
        if (updates.length > 0) moveObjects(updates);
      } else if (drag.kind === 'marquee' && variant) {
        const minX = Math.min(drag.startPointer.x, drag.currentPointer.x);
        const maxX = Math.max(drag.startPointer.x, drag.currentPointer.x);
        const minY = Math.min(drag.startPointer.y, drag.currentPointer.y);
        const maxY = Math.max(drag.startPointer.y, drag.currentPointer.y);
        const hits = variant.objects.filter(
          (o) => o.transform.x >= minX && o.transform.x <= maxX && o.transform.y >= minY && o.transform.y <= maxY,
        );
        if (hits.length > 0) select(hits.map((o) => o.id));
      }
      setLiveTransforms({});
      setDrag(null);
    };

    window.addEventListener('pointermove', handleMove);
    window.addEventListener('pointerup', handleUp);
    return () => {
      window.removeEventListener('pointermove', handleMove);
      window.removeEventListener('pointerup', handleUp);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [drag, liveTransforms, liveBoundary, snap, toWorld, moveObjects, select, variant, updatePlotBoundary, project.plot.boundary]);

  const gridLines = useMemo(() => {
    const lines: ReactElement[] = [];
    const startX = Math.floor((bounds.minX - PADDING_M) / gridSize) * gridSize;
    const endX = bounds.maxX + PADDING_M;
    const startY = Math.floor((bounds.minY - PADDING_M) / gridSize) * gridSize;
    const endY = bounds.maxY + PADDING_M;
    for (let x = startX; x <= endX; x += gridSize) {
      lines.push(<line key={`gx${x}`} x1={x} y1={startY} x2={x} y2={endY} className="stroke-stone-200 dark:stroke-stone-800" strokeWidth={0.03} />);
    }
    for (let y = startY; y <= endY; y += gridSize) {
      lines.push(<line key={`gy${y}`} x1={startX} y1={y} x2={endX} y2={y} className="stroke-stone-200 dark:stroke-stone-800" strokeWidth={0.03} />);
    }
    return lines;
  }, [bounds, gridSize]);

  const showDesignDetail = visualizationMode === 'design';
  const showUtilities = visualizationMode === 'utilities';
  const showRationale = visualizationMode === 'rationale';
  const activeSeason = visualizationMode === 'seasonal' ? season : undefined;

  if (!variant) {
    return <div className="flex h-full items-center justify-center text-sm text-stone-500">{t(locale, 'plan.noLayout')}</div>;
  }

  return (
    <div className="relative h-full w-full">
    <div className="h-full w-full overflow-auto bg-stone-50 dark:bg-stone-950">
      <svg
        ref={svgRef}
        viewBox={viewBox}
        width={worldW * PX_PER_METER * zoom}
        height={worldH * PX_PER_METER * zoom}
        onPointerDown={handleBackgroundPointerDown}
        className="block"
      >
        <g>{gridLines}</g>

        <ContourLines plot={project.plot} themeKey={themeKey} />

        {layerVisibility.water !== false && <WaterfrontZone plot={project.plot} themeKey={themeKey} locale={locale} />}

        {/* Future-expansion / area-only zones */}
        {variant.zones.map((z) => (
          <polygon
            key={z.id}
            points={z.boundary.map((p) => `${p.x},${p.y}`).join(' ')}
            fill={CATEGORY_STYLES[z.category][themeKey].fill}
            fillOpacity={0.35}
            stroke={CATEGORY_STYLES[z.category][themeKey].stroke}
            strokeWidth={0.12}
            strokeDasharray="0.6,0.4"
          />
        ))}

        {/* Fences */}
        {layerVisibility.fence !== false &&
          variant.fences
            .filter((f) => f.fenceType === 'perimeter' || !showUtilities)
            .map((f) => (
            <polygon
              key={f.id}
              points={f.points.map((p) => `${p.x},${p.y}`).join(' ')}
              fill="none"
              stroke={f.fenceType === 'perimeter' ? '#4a4a4a' : '#8a7050'}
              strokeWidth={f.fenceType === 'perimeter' ? 0.2 : 0.1}
              strokeDasharray={f.fenceType === 'perimeter' ? undefined : '0.3,0.3'}
            />
          ))}

        {/* Paths */}
        {layerVisibility.path !== false &&
          !showUtilities &&
          variant.paths.map((p) => {
            const style = pathStyle(p);
            const pointsAttr = p.points.map((pt) => `${pt.x},${pt.y}`).join(' ');
            return (
              <g key={p.id}>
                <polyline
                  points={pointsAttr}
                  fill="none"
                  stroke={style.stroke}
                  strokeWidth={style.strokeWidth}
                  strokeLinecap="butt"
                  strokeDasharray={style.dasharray}
                  opacity={style.opacity}
                />
                {p.category === 'service' && (
                  <polyline
                    points={pointsAttr}
                    fill="none"
                    stroke="#e8dfc8"
                    strokeWidth={0.08}
                    strokeDasharray="0.5,0.6"
                    strokeLinecap="butt"
                    opacity={0.8}
                  />
                )}
              </g>
            );
          })}

        {/* Gate: where the driveway/entrance path crosses the property line */}
        {layerVisibility.fence !== false && !showUtilities && variant.paths.find((p) => p.id === 'path-entrance') && (
          <GateGlyph
            plot={project.plot}
            point={variant.paths.find((p) => p.id === 'path-entrance')!.points[0]}
            bgColor={themeKey === 'dark' ? '#0c0a09' : '#fafaf9'}
          />
        )}

        {/* Utility hookups: power cable runs (amber) and water pipe runs (blue) */}
        {utilityLines
          .filter((l) => layerVisibility[l.kind === 'power' ? 'energy' : 'water'] !== false)
          .map((l) => (
            <line
              key={l.id}
              x1={l.x1}
              y1={l.y1}
              x2={l.x2}
              y2={l.y2}
              stroke={l.kind === 'power' ? '#b45309' : '#1d4ed8'}
              strokeWidth={l.kind === 'power' ? 0.14 : 0.11}
              strokeDasharray={l.kind === 'power' ? '0.5,0.35' : '0.12,0.3'}
              strokeLinecap="round"
              opacity={0.75}
            />
          ))}

        {/* Plot boundary */}
        <polygon
          points={(liveBoundary ?? project.plot.boundary).map((p) => `${p.x},${p.y}`).join(' ')}
          fill="none"
          stroke="currentColor"
          className="text-stone-800 dark:text-stone-200"
          strokeWidth={0.25}
        />

        {editingPlotShape && (() => {
          const poly = liveBoundary ?? project.plot.boundary;
          return (
            <g>
              {poly.map((p, i) => {
                const next = poly[(i + 1) % poly.length];
                const mid = { x: (p.x + next.x) / 2, y: (p.y + next.y) / 2 };
                return (
                  <rect
                    key={`plot-edge-${i}`}
                    x={mid.x - 0.35}
                    y={mid.y - 0.35}
                    width={0.7}
                    height={0.7}
                    fill="#2b6cb0"
                    fillOpacity={0.45}
                    className="cursor-copy"
                    onPointerDown={(e) => handlePlotEdgeInsert(e, i)}
                  />
                );
              })}
              {poly.map((p, i) => (
                <circle
                  key={`plot-vertex-${i}`}
                  cx={p.x}
                  cy={p.y}
                  r={0.55}
                  fill="#c0392b"
                  stroke="white"
                  strokeWidth={0.1}
                  className="cursor-grab"
                  onPointerDown={(e) => handlePlotVertexPointerDown(e, i)}
                  onDoubleClick={(e) => handlePlotVertexDoubleClick(e, i)}
                />
              ))}
            </g>
          );
        })()}

        {/* Objects */}
        {objects.map((obj) => {
          const category = obj.category as ZoneCategory;
          if (layerVisibility[obj.category] === false) return null;
          if (showUtilities && !['utility', 'energy', 'water'].includes(category)) return null;
          const isSelected = selectedObjectIds.includes(obj.id);
          const hasWarning = variant.warnings.some((w) => w.objectIds.includes(obj.id));
          const corners = rectCorners(obj.transform);

          return (
            <g
              key={obj.id}
              onPointerDown={(e) => !editingPlotShape && handleObjectPointerDown(e, obj)}
              className={editingPlotShape ? '' : 'cursor-move'}
            >
              <g transform={`translate(${obj.transform.x} ${obj.transform.y}) rotate(${obj.transform.rotationDeg})`}>
                <ObjectVisual
                  obj={obj}
                  themeKey={themeKey}
                  locale={locale}
                  showDesignDetail={showDesignDetail}
                  hasWarning={hasWarning}
                  isSelected={isSelected}
                  textClassName="select-none fill-stone-900 dark:fill-stone-100"
                  season={activeSeason}
                />
              </g>

              {showRationale && !obj.locked && Array.isArray(obj.metadata.rationaleTokens) && (
                <text x={obj.transform.x} y={obj.transform.y + obj.transform.height / 2 + 1.2} fontSize={0.55} textAnchor="middle" className="fill-stone-600">
                  {(() => {
                    const rationale = translateRationale(locale, obj.typeId, obj.metadata.rationaleTokens as string[]);
                    return rationale.length > 60 ? rationale.slice(0, 57) + '…' : rationale;
                  })()}
                </text>
              )}

              {isSelected && !obj.locked && !editingPlotShape && (
                <g>
                  {corners.map((c, i) => (
                    <rect
                      key={i}
                      x={c.x - 0.4}
                      y={c.y - 0.4}
                      width={0.8}
                      height={0.8}
                      fill="#2b6cb0"
                      className="cursor-nwse-resize"
                      onPointerDown={(e) => handleResizeStart(e, obj, i)}
                    />
                  ))}
                  <line
                    x1={obj.transform.x}
                    y1={obj.transform.y - obj.transform.height / 2}
                    x2={obj.transform.x}
                    y2={obj.transform.y - obj.transform.height / 2 - 1.5}
                    stroke="#2b6cb0"
                    strokeWidth={0.1}
                  />
                  <circle
                    cx={obj.transform.x}
                    cy={obj.transform.y - obj.transform.height / 2 - 1.5}
                    r={0.45}
                    fill="#2b6cb0"
                    className="cursor-grab"
                    onPointerDown={(e) => handleRotateStart(e, obj)}
                  />
                </g>
              )}
            </g>
          );
        })}

        {/* Marquee selection */}
        {drag?.kind === 'marquee' && (
          <rect
            x={Math.min(drag.startPointer.x, drag.currentPointer.x)}
            y={Math.min(drag.startPointer.y, drag.currentPointer.y)}
            width={Math.abs(drag.currentPointer.x - drag.startPointer.x)}
            height={Math.abs(drag.currentPointer.y - drag.startPointer.y)}
            fill="#2b6cb0"
            fillOpacity={0.1}
            stroke="#2b6cb0"
            strokeWidth={0.1}
          />
        )}

        <NorthArrow bounds={bounds} northAngleDeg={project.plot.northAngleDeg} locale={locale} />
        <ScaleBar bounds={bounds} />
      </svg>
    </div>
      {showLegend && <PlanLegend variant={variant} themeKey={themeKey} locale={locale} />}
    </div>
  );
}

function NorthArrow({ bounds, northAngleDeg, locale }: { bounds: ReturnType<typeof polygonBounds>; northAngleDeg: number; locale: Locale }) {
  const x = bounds.maxX + PADDING_M * 0.55;
  const y = bounds.minY + PADDING_M * 0.55;
  return (
    <g transform={`translate(${x} ${y}) rotate(${northAngleDeg})`}>
      <circle r={1.6} fill="white" fillOpacity={0.8} stroke="#555" strokeWidth={0.08} />
      <path d="M 0,-1.2 L 0.5,0.6 L 0,0.2 L -0.5,0.6 Z" fill="#333" />
      <text y={-1.9} textAnchor="middle" fontSize={0.8} fill="#333">{t(locale, 'plan.north')}</text>
    </g>
  );
}

function ScaleBar({ bounds }: { bounds: ReturnType<typeof polygonBounds> }) {
  const barLenM = 10;
  const x = bounds.minX;
  const y = bounds.maxY + PADDING_M * 0.75;
  return (
    <g transform={`translate(${x} ${y})`}>
      <line x1={0} y1={0} x2={barLenM} y2={0} stroke="#333" strokeWidth={0.15} />
      <line x1={0} y1={-0.3} x2={0} y2={0.3} stroke="#333" strokeWidth={0.1} />
      <line x1={barLenM} y1={-0.3} x2={barLenM} y2={0.3} stroke="#333" strokeWidth={0.1} />
      <text x={barLenM / 2} y={1.1} textAnchor="middle" fontSize={0.7} fill="#333">{barLenM} m</text>
    </g>
  );
}

function PlanLegend({ variant, themeKey, locale }: { variant: LayoutVariant; themeKey: 'light' | 'dark'; locale: Locale }) {
  const used = ZONE_CATEGORY_ORDER.filter(
    (c) => variant.objects.some((o) => o.category === c) || variant.zones.some((z) => z.category === c),
  );
  if (used.length === 0) return null;
  return (
    <div className="pointer-events-none absolute right-3 bottom-3 rounded-md border border-stone-300 bg-white/95 p-2.5 text-[11px] shadow-sm dark:border-stone-700 dark:bg-stone-900/95">
      <div className="mb-1 font-semibold text-stone-600 dark:text-stone-300">{t(locale, 'plan.legend')}</div>
      <div className="grid grid-cols-2 gap-x-3 gap-y-1">
        {used.map((c) => (
          <div key={c} className="flex items-center gap-1.5">
            <span
              className="h-2.5 w-2.5 shrink-0 rounded-sm border"
              style={{ backgroundColor: CATEGORY_STYLES[c][themeKey].fill, borderColor: CATEGORY_STYLES[c][themeKey].stroke }}
            />
            <span className="text-stone-600 dark:text-stone-300">{categoryLabel(locale, c)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
