import { useCallback, useEffect, useMemo, useRef, useState, type ReactElement } from 'react';
import { useProjectStore, getActiveVariant } from '../../state/projectStore';
import { CATEGORY_STYLES } from '../../domain/categories';
import { OBJECT_LIBRARY } from '../../domain/objectLibrary';
import type { PlanObject, Point, Transform, ZoneCategory } from '../../domain/types';
import { polygonBounds, rectCorners, resizeFromCorner } from '../../engine/geometry';

const PX_PER_METER = 12;
const PADDING_M = 6;

type DragMode =
  | { kind: 'move'; startPointer: Point; startTransforms: Record<string, Transform> }
  | { kind: 'resize'; objectId: string; cornerIndex: number; fixedCorner: Point; cornerSign: Point; rotationDeg: number }
  | { kind: 'rotate'; objectId: string; center: Point }
  | { kind: 'marquee'; startPointer: Point; currentPointer: Point };

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
  const visualizationMode = useProjectStore((s) => s.visualizationMode);
  const layerVisibility = useProjectStore((s) => s.layerVisibility);
  const snapToGrid = useProjectStore((s) => s.snapToGrid);
  const gridSize = useProjectStore((s) => s.gridSize);
  const zoom = useProjectStore((s) => s.zoom);
  const selectedObjectIds = useProjectStore((s) => s.selectedObjectIds);
  const select = useProjectStore((s) => s.select);
  const moveObjects = useProjectStore((s) => s.moveObjects);

  const svgRef = useRef<SVGSVGElement>(null);
  const [drag, setDrag] = useState<DragMode | null>(null);
  const [liveTransforms, setLiveTransforms] = useState<Record<string, Transform>>({});

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
    const p = toWorld(e.clientX, e.clientY);
    setDrag({ kind: 'marquee', startPointer: p, currentPointer: p });
    if (!e.shiftKey) select([]);
  };

  useEffect(() => {
    if (!drag || !variant) return;

    const handleMove = (e: PointerEvent) => {
      const p = toWorld(e.clientX, e.clientY);
      if (drag.kind === 'move') {
        const dx = snap(p.x - drag.startPointer.x);
        const dy = snap(p.y - drag.startPointer.y);
        const next: Record<string, Transform> = {};
        for (const [id, t] of Object.entries(drag.startTransforms)) {
          next[id] = { ...t, x: t.x + dx, y: t.y + dy };
        }
        setLiveTransforms(next);
      } else if (drag.kind === 'resize') {
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
      } else if (drag.kind === 'rotate') {
        const angle = (Math.atan2(p.y - drag.center.y, p.x - drag.center.x) * 180) / Math.PI + 90;
        const obj = variant.objects.find((o) => o.id === drag.objectId);
        if (obj) setLiveTransforms({ [drag.objectId]: { ...obj.transform, rotationDeg: Math.round(angle / 5) * 5 } });
      } else if (drag.kind === 'marquee') {
        setDrag({ ...drag, currentPointer: p });
      }
    };

    const handleUp = () => {
      if (drag.kind === 'move' || drag.kind === 'resize' || drag.kind === 'rotate') {
        const updates = Object.entries(liveTransforms).map(([id, transform]) => ({ id, transform }));
        if (updates.length > 0) moveObjects(updates);
      } else if (drag.kind === 'marquee') {
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
  }, [drag, liveTransforms, snap, toWorld, moveObjects, select, variant]);

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

  if (!variant) {
    return <div className="flex h-full items-center justify-center text-sm text-stone-500">No layout generated yet.</div>;
  }

  return (
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
          variant.paths.map((p) => (
            <polyline
              key={p.id}
              points={p.points.map((pt) => `${pt.x},${pt.y}`).join(' ')}
              fill="none"
              stroke="#c2b49a"
              strokeWidth={Math.min(0.6, p.widthM)}
              strokeLinecap="round"
              strokeDasharray="0.5,0.7"
              opacity={0.55}
            />
          ))}

        {/* Plot boundary */}
        <polygon
          points={project.plot.boundary.map((p) => `${p.x},${p.y}`).join(' ')}
          fill="none"
          stroke="currentColor"
          className="text-stone-800 dark:text-stone-200"
          strokeWidth={0.25}
        />

        {/* Objects */}
        {objects.map((obj) => {
          const category = obj.category as ZoneCategory;
          const style = CATEGORY_STYLES[category];
          if (layerVisibility[obj.category] === false) return null;
          if (showUtilities && !['utility', 'energy', 'water'].includes(category)) return null;
          const isSelected = selectedObjectIds.includes(obj.id);
          const hasWarning = variant.warnings.some((w) => w.objectIds.includes(obj.id));
          const corners = rectCorners(obj.transform);

          return (
            <g key={obj.id} onPointerDown={(e) => handleObjectPointerDown(e, obj)} className="cursor-move">
              <g transform={`translate(${obj.transform.x} ${obj.transform.y}) rotate(${obj.transform.rotationDeg})`}>
                <rect
                  x={-obj.transform.width / 2}
                  y={-obj.transform.height / 2}
                  width={obj.transform.width}
                  height={obj.transform.height}
                  fill={style?.[themeKey].fill ?? '#ddd'}
                  fillOpacity={obj.locked ? 0.5 : 0.85}
                  stroke={hasWarning ? '#b3452e' : style?.[themeKey].stroke ?? '#888'}
                  strokeWidth={isSelected ? 0.3 : 0.15}
                  strokeDasharray={obj.locked ? '0.4,0.3' : undefined}
                  rx={0.2}
                />
                {showDesignDetail && (
                  <rect
                    x={-obj.transform.width / 2 + 0.3}
                    y={-obj.transform.height / 2 + 0.3}
                    width={Math.max(0, obj.transform.width - 0.6)}
                    height={Math.max(0, obj.transform.height - 0.6)}
                    fill="none"
                    stroke={style?.[themeKey].stroke ?? '#888'}
                    strokeWidth={0.06}
                    strokeDasharray="0.2,0.2"
                  />
                )}
                <text
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontSize={Math.min(1.6, Math.max(0.7, Math.min(obj.transform.width, obj.transform.height) / 4))}
                  className="select-none fill-stone-900 dark:fill-stone-100"
                  transform={`rotate(${-obj.transform.rotationDeg})`}
                >
                  {obj.label}
                </text>
                {hasWarning && (
                  <circle cx={obj.transform.width / 2 - 0.5} cy={-obj.transform.height / 2 + 0.5} r={0.35} fill="#b3452e" />
                )}
              </g>

              {showRationale && obj.rationale && !obj.locked && (
                <text x={obj.transform.x} y={obj.transform.y + obj.transform.height / 2 + 1.2} fontSize={0.55} textAnchor="middle" className="fill-stone-600">
                  {obj.rationale.length > 60 ? obj.rationale.slice(0, 57) + '…' : obj.rationale}
                </text>
              )}

              {isSelected && !obj.locked && (
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

        <NorthArrow bounds={bounds} northAngleDeg={project.plot.northAngleDeg} />
        <ScaleBar bounds={bounds} />
      </svg>
    </div>
  );
}

function NorthArrow({ bounds, northAngleDeg }: { bounds: ReturnType<typeof polygonBounds>; northAngleDeg: number }) {
  const x = bounds.maxX + PADDING_M * 0.55;
  const y = bounds.minY + PADDING_M * 0.55;
  return (
    <g transform={`translate(${x} ${y}) rotate(${northAngleDeg})`}>
      <circle r={1.6} fill="white" fillOpacity={0.8} stroke="#555" strokeWidth={0.08} />
      <path d="M 0,-1.2 L 0.5,0.6 L 0,0.2 L -0.5,0.6 Z" fill="#333" />
      <text y={-1.9} textAnchor="middle" fontSize={0.8} fill="#333">N</text>
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
