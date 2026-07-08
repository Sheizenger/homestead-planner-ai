import { create } from 'zustand';
import { produce } from 'immer';
import { v4 as uuid } from 'uuid';
import type {
  EditSnapshot,
  LayoutVariant,
  ObjectCategory,
  PlanningMode,
  Plot,
  Project,
  Transform,
  VisualizationMode,
  ZoneCategory,
} from '../domain/types';
import { ZONE_CATEGORY_ORDER } from '../domain/categories';
import { createBlankProject, createSampleProject } from '../data/sampleProject';
import { generateVariants, generateVariant } from '../engine/generate';
import { computeAnalytics } from '../engine/analytics';
import { computeWarnings } from '../engine/warnings';
import { transformAabb, aabbOverlap } from '../engine/geometry';

const HISTORY_LIMIT = 40;

function snapshotOf(v: LayoutVariant): EditSnapshot {
  return {
    zones: v.zones,
    objects: v.objects,
    paths: v.paths,
    fences: v.fences,
    utilityNodes: v.utilityNodes,
  };
}

function applySnapshot(v: LayoutVariant, snap: EditSnapshot, plot: Plot): LayoutVariant {
  const analytics = computeAnalytics(snap.objects, snap.zones, plot);
  const warnings = computeWarnings(snap.objects, snap.fences, analytics);
  return { ...v, ...snap, analytics, warnings };
}

type Theme = 'light' | 'dark';

interface ProjectState {
  project: Project;
  theme: Theme;
  visualizationMode: VisualizationMode;
  selectedObjectIds: string[];
  layerVisibility: Record<ObjectCategory, boolean>;
  layerLocked: Record<ObjectCategory, boolean>;
  snapToGrid: boolean;
  gridSize: number;
  zoom: number;
  comparisonIds: string[];
  view: 'workspace' | 'comparison';
  isExportOpen: boolean;
  generating: boolean;

  loadSample: () => void;
  newProject: (name: string, width: number, height: number) => void;
  updateFreeText: (text: string) => void;
  updateStructuredInputs: (patch: Partial<Project['brief']['structuredInputs']>) => void;
  generate: (mode?: PlanningMode) => void;
  regenerateVariant: (variantId: string) => void;
  setActiveVariant: (id: string) => void;
  select: (ids: string[]) => void;
  updateObjectTransform: (objectId: string, transform: Partial<Transform>) => void;
  moveObjects: (updates: { id: string; transform: Transform }[]) => void;
  deleteObjects: (ids: string[]) => void;
  duplicateObjects: (ids: string[]) => void;
  toggleLock: (objectId: string) => void;
  toggleLayerVisibility: (category: ObjectCategory) => void;
  toggleLayerLock: (category: ObjectCategory) => void;
  undo: () => void;
  redo: () => void;
  setVisualizationMode: (mode: VisualizationMode) => void;
  setTheme: (theme: Theme) => void;
  toggleSnap: () => void;
  setGridSize: (n: number) => void;
  setZoom: (z: number) => void;
  setView: (v: 'workspace' | 'comparison') => void;
  setComparisonIds: (ids: string[]) => void;
  copyObjectToActive: (fromVariantId: string, objectId: string) => void;
  setExportOpen: (open: boolean) => void;
}

function defaultVisibility(): Record<ObjectCategory, boolean> {
  const cats: ObjectCategory[] = [...ZONE_CATEGORY_ORDER, 'fence', 'path'];
  return Object.fromEntries(cats.map((c) => [c, true])) as Record<ObjectCategory, boolean>;
}

function defaultLocked(): Record<ObjectCategory, boolean> {
  const cats: ObjectCategory[] = [...ZONE_CATEGORY_ORDER, 'fence', 'path'];
  return Object.fromEntries(cats.map((c) => [c, false])) as Record<ObjectCategory, boolean>;
}

function withActiveVariant(project: Project, updater: (v: LayoutVariant, plot: Plot) => LayoutVariant): Project {
  return {
    ...project,
    updatedAt: new Date().toISOString(),
    variants: project.variants.map((v) => (v.id === project.activeVariantId ? updater(v, project.plot) : v)),
  };
}

function pushHistory(v: LayoutVariant): LayoutVariant {
  const past = [...v.history.past, snapshotOf(v)].slice(-HISTORY_LIMIT);
  return { ...v, history: { past, future: [] } };
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  project: (() => {
    const p = createSampleProject();
    return p;
  })(),
  theme: 'light',
  visualizationMode: 'schematic',
  selectedObjectIds: [],
  layerVisibility: defaultVisibility(),
  layerLocked: defaultLocked(),
  snapToGrid: true,
  gridSize: 1,
  zoom: 1,
  comparisonIds: [],
  view: 'workspace',
  isExportOpen: false,
  generating: false,

  loadSample: () => {
    const project = createSampleProject();
    set({ project, selectedObjectIds: [] });
    get().generate();
  },

  newProject: (name, width, height) => {
    const project = createBlankProject(name, width, height);
    set({ project, selectedObjectIds: [] });
  },

  updateFreeText: (text) =>
    set(
      produce((state: ProjectState) => {
        state.project.brief.freeText = text;
      }),
    ),

  updateStructuredInputs: (patch) =>
    set(
      produce((state: ProjectState) => {
        Object.assign(state.project.brief.structuredInputs, patch);
      }),
    ),

  generate: (mode) => {
    set({ generating: true });
    const project = get().project;
    const variants = generateVariants(project, mode);
    set({
      project: { ...project, variants, activeVariantId: variants[0].id, updatedAt: new Date().toISOString() },
      selectedObjectIds: [],
      generating: false,
      comparisonIds: variants.map((v) => v.id),
    });
  },

  regenerateVariant: (variantId) => {
    const project = get().project;
    const existing = project.variants.find((v) => v.id === variantId);
    if (!existing) return;
    const fresh = generateVariant(project, existing.mode, Math.floor(Math.random() * 100000));
    set({
      project: {
        ...project,
        variants: project.variants.map((v) => (v.id === variantId ? fresh : v)),
        updatedAt: new Date().toISOString(),
      },
    });
  },

  setActiveVariant: (id) => set({ selectedObjectIds: [], project: { ...get().project, activeVariantId: id } }),

  select: (ids) => set({ selectedObjectIds: ids }),

  updateObjectTransform: (objectId, transform) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, plot) => {
        const withHistory = pushHistory(v);
        const objects = withHistory.objects.map((o) =>
          o.id === objectId && !o.locked ? { ...o, transform: { ...o.transform, ...transform } } : o,
        );
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, plot);
      }),
    })),

  moveObjects: (updates) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, plot) => {
        const withHistory = pushHistory(v);
        const byId = new Map(updates.map((u) => [u.id, u.transform]));
        const objects = withHistory.objects.map((o) =>
          byId.has(o.id) && !o.locked ? { ...o, transform: byId.get(o.id)! } : o,
        );
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, plot);
      }),
    })),

  deleteObjects: (ids) =>
    set((state) => ({
      selectedObjectIds: [],
      project: withActiveVariant(state.project, (v, plot) => {
        const withHistory = pushHistory(v);
        const objects = withHistory.objects.filter((o) => !ids.includes(o.id) || o.locked);
        const fences = withHistory.fences.filter((f) => !ids.some((id) => f.id === `fence-${id}`));
        const paths = withHistory.paths.filter((p) => !ids.some((id) => p.id === `path-${id}`));
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects, fences, paths }, plot);
      }),
    })),

  duplicateObjects: (ids) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, plot) => {
        const withHistory = pushHistory(v);
        const clones = withHistory.objects
          .filter((o) => ids.includes(o.id))
          .map((o) => ({
            ...o,
            id: `obj-${uuid()}`,
            locked: false,
            transform: { ...o.transform, x: o.transform.x + 2, y: o.transform.y + 2 },
          }));
        const objects = [...withHistory.objects, ...clones];
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, plot);
      }),
    })),

  toggleLock: (objectId) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v) => ({
        ...v,
        objects: v.objects.map((o) => (o.id === objectId ? { ...o, locked: !o.locked } : o)),
      })),
    })),

  toggleLayerVisibility: (category) =>
    set((state) => ({ layerVisibility: { ...state.layerVisibility, [category]: !state.layerVisibility[category] } })),

  toggleLayerLock: (category) =>
    set((state) => ({ layerLocked: { ...state.layerLocked, [category]: !state.layerLocked[category] } })),

  undo: () =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, plot) => {
        if (v.history.past.length === 0) return v;
        const prev = v.history.past[v.history.past.length - 1];
        const past = v.history.past.slice(0, -1);
        const future = [snapshotOf(v), ...v.history.future].slice(0, HISTORY_LIMIT);
        return applySnapshot({ ...v, history: { past, future } }, prev, plot);
      }),
    })),

  redo: () =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, plot) => {
        if (v.history.future.length === 0) return v;
        const next = v.history.future[0];
        const future = v.history.future.slice(1);
        const past = [...v.history.past, snapshotOf(v)].slice(-HISTORY_LIMIT);
        return applySnapshot({ ...v, history: { past, future } }, next, plot);
      }),
    })),

  setVisualizationMode: (mode) => set({ visualizationMode: mode }),
  setTheme: (theme) => set({ theme }),
  toggleSnap: () => set((s) => ({ snapToGrid: !s.snapToGrid })),
  setGridSize: (n) => set({ gridSize: n }),
  setZoom: (z) => set({ zoom: Math.max(0.3, Math.min(4, z)) }),
  setView: (v) => set({ view: v }),
  setComparisonIds: (ids) => set({ comparisonIds: ids }),

  copyObjectToActive: (fromVariantId, objectId) =>
    set((state) => {
      const source = state.project.variants.find((v) => v.id === fromVariantId);
      const obj = source?.objects.find((o) => o.id === objectId);
      if (!obj) return state;
      return {
        project: withActiveVariant(state.project, (v, plot) => {
          const aabb = transformAabb(obj.transform);
          const collides = v.objects.some((o) => aabbOverlap(aabb, transformAabb(o.transform)));
          if (collides) return v;
          const withHistory = pushHistory(v);
          const clone = { ...obj, id: `obj-${uuid()}`, locked: false };
          const objects = [...withHistory.objects, clone];
          return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, plot);
        }),
      };
    }),

  setExportOpen: (open) => set({ isExportOpen: open }),
}));

export function getActiveVariant(project: Project): LayoutVariant | undefined {
  return project.variants.find((v) => v.id === project.activeVariantId);
}

export function categoryLabel(c: ZoneCategory): string {
  return c
    .split('-')
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(' ');
}
