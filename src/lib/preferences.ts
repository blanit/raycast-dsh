import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { getPreferenceValues } from "@raycast/api";

interface Preferences {
  executablePath?: string;
  processName?: string;
  launchIfNotRunning?: boolean;
  launchTimeout?: string;
}

export interface Settings {
  processName: string;
  /** Resolved path to the shell executable, or an empty string when it could not be found. */
  executablePath: string;
  launchIfNotRunning: boolean;
  launchTimeoutMs: number;
}

const DEFAULT_PROCESS_NAME = "DeepSeek Harness";
const DEFAULT_LAUNCH_SECONDS = 15;

/**
 * Locations the DeepSeek Harness installer uses. Missing every candidate is not fatal: the
 * desktop build registers the `dsh://` protocol, and the helper launches through it instead.
 */
function executableCandidates(): string[] {
  const localAppData =
    process.env.LOCALAPPDATA?.trim() || join(homedir(), "AppData", "Local");
  const programFiles = process.env.ProgramFiles?.trim() || "C:\\Program Files";
  return [
    join(
      localAppData,
      "Programs",
      DEFAULT_PROCESS_NAME,
      `${DEFAULT_PROCESS_NAME}.exe`,
    ),
    join(programFiles, DEFAULT_PROCESS_NAME, `${DEFAULT_PROCESS_NAME}.exe`),
  ];
}

export function readSettings(): Settings {
  const preferences = getPreferenceValues<Preferences>();
  const configured = preferences.executablePath?.trim() ?? "";
  return {
    processName: preferences.processName?.trim() || DEFAULT_PROCESS_NAME,
    executablePath:
      configured ||
      executableCandidates().find((candidate) => existsSync(candidate)) ||
      "",
    launchIfNotRunning: preferences.launchIfNotRunning ?? true,
    launchTimeoutMs: parseSeconds(preferences.launchTimeout) * 1000,
  };
}

function parseSeconds(value: string | undefined): number {
  const seconds = Number.parseInt((value ?? "").trim(), 10);
  if (!Number.isFinite(seconds) || seconds <= 0) return DEFAULT_LAUNCH_SECONDS;
  return Math.min(seconds, 120);
}
