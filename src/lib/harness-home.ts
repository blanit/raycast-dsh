import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface HarnessHome {
  path: string;
  exists: boolean;
  /** Profile names under `<home>/profiles`, without the shared node_modules directory. */
  profiles: string[];
  /** Workspace folders that hold sessions. */
  workspaces: number;
  /** Session directories across every workspace. */
  sessions: number;
}

/**
 * Describe the local harness home.
 *
 * DSH_HOME is honoured when it is set, which is the case when Raycast itself was started from a
 * DSH shell; otherwise the default `~/.dsh` is used, which is where the desktop app keeps its
 * profiles, sessions and caches.
 */
export function readHarnessHome(): HarnessHome {
  const path = process.env.DSH_HOME?.trim() || join(homedir(), ".dsh");
  const home: HarnessHome = {
    path,
    exists: false,
    profiles: [],
    workspaces: 0,
    sessions: 0,
  };
  const sessionsRoot = join(path, "sessions");

  home.exists = existsSync(path);
  if (!home.exists) return home;

  home.profiles = listDirectories(join(path, "profiles")).filter(
    (name) => name !== "node_modules",
  );

  const workspaces = listDirectories(sessionsRoot);
  home.workspaces = workspaces.length;
  home.sessions = workspaces.reduce(
    (total, workspace) =>
      total +
      listDirectories(join(sessionsRoot, workspace)).filter((name) =>
        name.startsWith("session-"),
      ).length,
    0,
  );
  return home;
}

/** Names of the immediate subdirectories, or an empty list when the directory is unreadable. */
function listDirectories(path: string): string[] {
  try {
    return readdirSync(path, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}
