import { create } from 'zustand';
import { produce } from 'immer';
import { v4 as uuid } from 'uuid';
import type {
  EditSnapshot,
  LayoutVariant,
  ObjectCategory,
  PlanningMode,
  PlotElevation,
  Point,
  Project,
  Season,
  Transform,
  VisualizationMode,
  Waterfront,
  ZoneCategory,
} from '../domain/types';
import { ZONE_CATEGORY_ORDER } from '../domain/categories';
import { createBlankProject, createSampleProject } from '../data/sampleProject';
import { PROJECT_TEMPLATES, buildProjectFromTemplate } from '../data/templates';
import { generateVariants, generateVariant } from '../engine/generate';
import { computeAnalytics } from '../engine/analytics';
import { computeWarnings } from '../engine/warnings';
import { transformAabb, aabbOverlap, polygonBounds } from '../engine/geometry';
import {
  saveProject,
  loadProject,
  listProjects,
  deleteProject,
  getLastActiveProjectId,
  getStoredLocale,
  setStoredLocale,
  debounce,
  type ProjectSummary,
} from './persistence';
import { type Locale, LOCALES } from '../i18n/translations';
import { categoryLabel as translateCategoryLabel } from '../i18n/labels';

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

function applySnapshot(v: LayoutVariant, snap: EditSnapshot, project: Project): LayoutVariant {
  const analytics = computeAnalytics(snap.objects, snap.zones, project.plot);
  const warnings = computeWarnings(
    snap.objects,
    snap.fences,
    analytics,
    project.plot,
    project.brief.structuredInputs.householdSize,
    project.brief.structuredInputs.climateZone,
    project.brief.structuredInputs.crops,
  );
  return { ...v, ...snap, analytics, warnings };
}

type Theme = 'light' | 'dark';

// A user-uploaded reference image (e.g. a satellite/map screenshot) shown as
// a positionable, scalable backdrop on the canvas so the plot boundary can
// be traced over it with the existing polygon vertex editor. Deliberately
// NOT part of Project/Plot — it's a session-only tracing aid (kept out of
// the persisted/autosaved project so a large data URL never bloats
// localStorage), not plan data.
export interface TraceImage {
  dataUrl: string;
  naturalWidthPx: number;
  naturalHeightPx: number;
  xM: number;
  yM: number;
  widthM: number;
  opacity: number;
}

function loadInitialLocale(): Locale {
  const stored = getStoredLocale();
  if (stored && (LOCALES as string[]).includes(stored)) return stored as Locale;
  return 'en';
}

interface ProjectState {
  project: Project;
  theme: Theme;
  locale: Locale;
  visualizationMode: VisualizationMode;
  season: Season;
  selectedObjectIds: string[];
  layerVisibility: Record<ObjectCategory, boolean>;
  layerLocked: Record<ObjectCategory, boolean>;
  snapToGrid: boolean;
  gridSize: number;
  zoom: number;
  showLegend: boolean;
  comparisonIds: string[];
  view: 'workspace' | 'comparison';
  isExportOpen: boolean;
  isCostOpen: boolean;
  costRegionId: string;
  customLandPriceUsd: number;
  isProjectsOpen: boolean;
  generating: boolean;

  loadSample: () => void;
  newProject: (name: string, width: number, height: number) => void;
  newProjectFromTemplate: (templateId: string, name: string, width: number, height: number) => void;
  switchToProject: (id: string) => void;
  deleteSavedProject: (id: string) => void;
  importProjectFromJson: (json: string) => { ok: true } | { ok: false; error: string };
  getSavedProjects: () => ProjectSummary[];
  setProjectsOpen: (open: boolean) => void;
  updateFreeText: (text: string) => void;
  updateStructuredInputs: (patch: Partial<Project['brief']['structuredInputs']>) => void;
  updatePlotSize: (width: number, height: number) => void;
  updatePlotBoundary: (boundary: Point[]) => void;
  editingPlotShape: boolean;
  toggleEditingPlotShape: () => void;
  traceImage: TraceImage | null;
  setTraceImage: (image: { dataUrl: string; naturalWidthPx: number; naturalHeightPx: number }) => void;
  updateTraceImage: (patch: Partial<Pick<TraceImage, 'xM' | 'yM' | 'widthM' | 'opacity'>>) => void;
  clearTraceImage: () => void;
  updateWaterfront: (waterfront: Waterfront | null) => void;
  updateElevation: (elevation: PlotElevation | null) => void;
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
  setSeason: (season: Season) => void;
  setTheme: (theme: Theme) => void;
  setLocale: (locale: Locale) => void;
  toggleSnap: () => void;
  toggleLegend: () => void;
  setGridSize: (n: number) => void;
  setZoom: (z: number) => void;
  setView: (v: 'workspace' | 'comparison') => void;
  setComparisonIds: (ids: string[]) => void;
  copyObjectToActive: (fromVariantId: string, objectId: string) => void;
  setExportOpen: (open: boolean) => void;
  setCostOpen: (open: boolean) => void;
  setCostRegion: (id: string) => void;
  setCustomLandPrice: (usd: number) => void;
}

function defaultVisibility(): Record<ObjectCategory, boolean> {
  const cats: ObjectCategory[] = [...ZONE_CATEGORY_ORDER, 'fence', 'path'];
  return Object.fromEntries(cats.map((c) => [c, true])) as Record<ObjectCategory, boolean>;
}

function defaultLocked(): Record<ObjectCategory, boolean> {
  const cats: ObjectCategory[] = [...ZONE_CATEGORY_ORDER, 'fence', 'path'];
  return Object.fromEntries(cats.map((c) => [c, false])) as Record<ObjectCategory, boolean>;
}

function withActiveVariant(project: Project, updater: (v: LayoutVariant, project: Project) => LayoutVariant): Project {
  return {
    ...project,
    updatedAt: new Date().toISOString(),
    variants: project.variants.map((v) => (v.id === project.activeVariantId ? updater(v, project) : v)),
  };
}

function pushHistory(v: LayoutVariant): LayoutVariant {
  const past = [...v.history.past, snapshotOf(v)].slice(-HISTORY_LIMIT);
  return { ...v, history: { past, future: [] } };
}

function loadInitialProject(): Project {
  const lastId = getLastActiveProjectId();
  const restored = lastId ? loadProject(lastId) : null;
  if (restored) return restored;
  const sample = createSampleProject();
  saveProject(sample);
  return sample;
}

function isProject(value: unknown): value is Project {
  if (!value || typeof value !== 'object') return false;
  const p = value as Record<string, unknown>;
  return typeof p.id === 'string' && typeof p.name === 'string' && !!p.plot && Array.isArray(p.variants) && !!p.brief;
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  project: loadInitialProject(),
  theme: 'light',
  locale: loadInitialLocale(),
  visualizationMode: 'schematic',
  season: 'summer',
  selectedObjectIds: [],
  layerVisibility: defaultVisibility(),
  layerLocked: defaultLocked(),
  snapToGrid: true,
  gridSize: 1,
  zoom: 1,
  showLegend: false,
  comparisonIds: [],
  view: 'workspace',
  isExportOpen: false,
  isCostOpen: false,
  costRegionId: 'custom',
  customLandPriceUsd: 5,
  isProjectsOpen: false,
  generating: false,
  editingPlotShape: false,
  traceImage: null,

  loadSample: () => {
    const project = createSampleProject();
    set({ project, selectedObjectIds: [] });
    get().generate();
  },

  newProject: (name, width, height) => {
    const project = createBlankProject(name, width, height);
    set({ project, selectedObjectIds: [], isProjectsOpen: false });
  },

  newProjectFromTemplate: (templateId, name, width, height) => {
    const template = PROJECT_TEMPLATES.find((t) => t.id === templateId);
    const project = template
      ? buildProjectFromTemplate(template, name, width, height)
      : createBlankProject(name, width, height);
    set({ project, selectedObjectIds: [], isProjectsOpen: false });
  },

  switchToProject: (id) => {
    const project = loadProject(id);
    if (!project) return;
    set({ project, selectedObjectIds: [], isProjectsOpen: false });
  },

  deleteSavedProject: (id) => {
    deleteProject(id);
    if (get().project.id === id) {
      const remaining = listProjects();
      if (remaining.length > 0) {
        const next = loadProject(remaining[0].id);
        if (next) {
          set({ project: next, selectedObjectIds: [] });
          return;
        }
      }
      const sample = createSampleProject();
      saveProject(sample);
      set({ project: sample, selectedObjectIds: [] });
    }
  },

  importProjectFromJson: (json) => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch {
      return { ok: false, error: 'Not valid JSON.' };
    }
    if (!isProject(parsed)) return { ok: false, error: "Doesn't look like a Homestead Planner project file." };
    set({ project: parsed, selectedObjectIds: [], isProjectsOpen: false });
    return { ok: true };
  },

  getSavedProjects: () => listProjects(),
  setProjectsOpen: (open) => set({ isProjectsOpen: open }),

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

  updatePlotSize: (width, height) =>
    set((state) => ({
      project: {
        ...state.project,
        updatedAt: new Date().toISOString(),
        plot: {
          ...state.project.plot,
          boundary: [
            { x: 0, y: 0 },
            { x: width, y: 0 },
            { x: width, y: height },
            { x: 0, y: height },
          ],
        },
      },
    })),

  updatePlotBoundary: (boundary) =>
    set((state) => ({
      project: {
        ...state.project,
        updatedAt: new Date().toISOString(),
        plot: { ...state.project.plot, boundary },
      },
    })),

  toggleEditingPlotShape: () => set((s) => ({ editingPlotShape: !s.editingPlotShape })),

  setTraceImage: (image) =>
    set((state) => {
      const bounds = polygonBounds(state.project.plot.boundary);
      return {
        traceImage: {
          ...image,
          xM: bounds.minX,
          yM: bounds.minY,
          widthM: bounds.maxX - bounds.minX,
          opacity: 0.6,
        },
      };
    }),

  updateTraceImage: (patch) => set((state) => (state.traceImage ? { traceImage: { ...state.traceImage, ...patch } } : {})),

  clearTraceImage: () => set({ traceImage: null }),

  updateWaterfront: (waterfront) =>
    set((state) => ({
      project: {
        ...state.project,
        updatedAt: new Date().toISOString(),
        plot: { ...state.project.plot, waterfront: waterfront ?? undefined },
      },
    })),

  updateElevation: (elevation) =>
    set((state) => ({
      project: {
        ...state.project,
        updatedAt: new Date().toISOString(),
        plot: { ...state.project.plot, elevation: elevation ?? undefined },
      },
    })),

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
      project: withActiveVariant(state.project, (v, project) => {
        const withHistory = pushHistory(v);
        const objects = withHistory.objects.map((o) =>
          o.id === objectId && !o.locked ? { ...o, transform: { ...o.transform, ...transform } } : o,
        );
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, project);
      }),
    })),

  moveObjects: (updates) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, project) => {
        const withHistory = pushHistory(v);
        const byId = new Map(updates.map((u) => [u.id, u.transform]));
        const objects = withHistory.objects.map((o) =>
          byId.has(o.id) && !o.locked ? { ...o, transform: byId.get(o.id)! } : o,
        );
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, project);
      }),
    })),

  deleteObjects: (ids) =>
    set((state) => ({
      selectedObjectIds: [],
      project: withActiveVariant(state.project, (v, project) => {
        const withHistory = pushHistory(v);
        const objects = withHistory.objects.filter((o) => !ids.includes(o.id) || o.locked);
        const fences = withHistory.fences.filter((f) => !ids.some((id) => f.id === `fence-${id}`));
        const paths = withHistory.paths.filter((p) => !ids.some((id) => p.id === `path-${id}`));
        const remainingNodes = withHistory.utilityNodes.filter((n) => !ids.includes(n.objectId));
        const remainingIds = new Set(remainingNodes.map((n) => n.id));
        const utilityNodes = remainingNodes.map((n) => ({ ...n, connections: n.connections.filter((id) => remainingIds.has(id)) }));
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects, fences, paths, utilityNodes }, project);
      }),
    })),

  duplicateObjects: (ids) =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, project) => {
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
        return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, project);
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
      project: withActiveVariant(state.project, (v, project) => {
        if (v.history.past.length === 0) return v;
        const prev = v.history.past[v.history.past.length - 1];
        const past = v.history.past.slice(0, -1);
        const future = [snapshotOf(v), ...v.history.future].slice(0, HISTORY_LIMIT);
        return applySnapshot({ ...v, history: { past, future } }, prev, project);
      }),
    })),

  redo: () =>
    set((state) => ({
      project: withActiveVariant(state.project, (v, project) => {
        if (v.history.future.length === 0) return v;
        const next = v.history.future[0];
        const future = v.history.future.slice(1);
        const past = [...v.history.past, snapshotOf(v)].slice(-HISTORY_LIMIT);
        return applySnapshot({ ...v, history: { past, future } }, next, project);
      }),
    })),

  setVisualizationMode: (mode) => set({ visualizationMode: mode }),
  setSeason: (season) => set({ season }),
  setTheme: (theme) => set({ theme }),
  setLocale: (locale) => {
    setStoredLocale(locale);
    set({ locale });
  },
  toggleSnap: () => set((s) => ({ snapToGrid: !s.snapToGrid })),
  toggleLegend: () => set((s) => ({ showLegend: !s.showLegend })),
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
        project: withActiveVariant(state.project, (v, project) => {
          const aabb = transformAabb(obj.transform);
          const collides = v.objects.some((o) => aabbOverlap(aabb, transformAabb(o.transform)));
          if (collides) return v;
          const withHistory = pushHistory(v);
          const clone = { ...obj, id: `obj-${uuid()}`, locked: false };
          const objects = [...withHistory.objects, clone];
          return applySnapshot(withHistory, { ...snapshotOf(withHistory), objects }, project);
        }),
      };
    }),

  setExportOpen: (open) => set({ isExportOpen: open }),
  setCostOpen: (open) => set({ isCostOpen: open }),
  setCostRegion: (id) => set({ costRegionId: id }),
  setCustomLandPrice: (usd) => set({ customLandPriceUsd: usd }),
}));

const debouncedSaveProject = debounce((project: Project) => saveProject(project), 600);
let lastSavedProject: Project | null = null;
useProjectStore.subscribe((state) => {
  if (state.project !== lastSavedProject) {
    lastSavedProject = state.project;
    debouncedSaveProject(state.project);
  }
});

export function getActiveVariant(project: Project): LayoutVariant | undefined {
  return project.variants.find((v) => v.id === project.activeVariantId);
}

export function categoryLabel(locale: Locale, c: ZoneCategory): string {
  return translateCategoryLabel(locale, c);
}
