import type { Project } from '../domain/types';

const INDEX_KEY = 'homestead-planner:projects';
const LAST_ACTIVE_KEY = 'homestead-planner:last-active';
const projectKey = (id: string) => `homestead-planner:project:${id}`;

export interface ProjectSummary {
  id: string;
  name: string;
  updatedAt: string;
}

function readIndex(): ProjectSummary[] {
  try {
    const raw = localStorage.getItem(INDEX_KEY);
    return raw ? (JSON.parse(raw) as ProjectSummary[]) : [];
  } catch {
    return [];
  }
}

function writeIndex(index: ProjectSummary[]) {
  localStorage.setItem(INDEX_KEY, JSON.stringify(index));
}

export function saveProject(project: Project) {
  try {
    localStorage.setItem(projectKey(project.id), JSON.stringify(project));
    const index = readIndex().filter((p) => p.id !== project.id);
    index.push({ id: project.id, name: project.name, updatedAt: project.updatedAt });
    writeIndex(index);
    localStorage.setItem(LAST_ACTIVE_KEY, project.id);
  } catch {
    // localStorage can throw (quota exceeded, private browsing) — autosave
    // failing silently is preferable to crashing the app mid-edit.
  }
}

export function loadProject(id: string): Project | null {
  try {
    const raw = localStorage.getItem(projectKey(id));
    return raw ? (JSON.parse(raw) as Project) : null;
  } catch {
    return null;
  }
}

export function listProjects(): ProjectSummary[] {
  return readIndex().sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export function deleteProject(id: string) {
  localStorage.removeItem(projectKey(id));
  writeIndex(readIndex().filter((p) => p.id !== id));
  if (localStorage.getItem(LAST_ACTIVE_KEY) === id) localStorage.removeItem(LAST_ACTIVE_KEY);
}

export function getLastActiveProjectId(): string | null {
  return localStorage.getItem(LAST_ACTIVE_KEY);
}

const LOCALE_KEY = 'homestead-planner:locale';

// The UI language is a browser-level preference, not part of any one
// project, so it's stored separately and survives switching/creating projects.
export function getStoredLocale(): string | null {
  try {
    return localStorage.getItem(LOCALE_KEY);
  } catch {
    return null;
  }
}

export function setStoredLocale(locale: string) {
  try {
    localStorage.setItem(LOCALE_KEY, locale);
  } catch {
    // ignore — same quota/private-browsing tolerance as project autosave
  }
}

export function debounce<Args extends unknown[]>(fn: (...args: Args) => void, ms: number) {
  let handle: ReturnType<typeof setTimeout> | null = null;
  return (...args: Args) => {
    if (handle) clearTimeout(handle);
    handle = setTimeout(() => fn(...args), ms);
  };
}
