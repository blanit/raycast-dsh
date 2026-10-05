import { execFile } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { environment } from "@raycast/api";

/** Every action the Win32 helper understands. */
export type WindowAction = "status" | "show" | "hide" | "toggle";

/** The window situations the helper can report. */
export type WindowStateName =
  "not-running" | "no-window" | "hidden" | "minimized" | "visible" | "active";

/** What the helper actually did. */
export type WindowResult =
  "reported" | "shown" | "hidden" | "launched" | "noop";

export interface WindowReport {
  ok: boolean;
  action: string;
  result: WindowResult;
  state: WindowStateName;
  running: boolean;
  processCount: number;
  processId: number;
  hasWindow: boolean;
  hwnd: string;
  visible: boolean;
  minimized: boolean;
  foreground: boolean;
  /** Whether this is the window the user is looking at, launcher tool windows aside. */
  inFront: boolean;
  title: string;
  executable: string;
  message: string;
}

export interface WindowRequest {
  /** Image name of the desktop shell, without the .exe extension. */
  processName: string;
  /** Full path to the shell executable; empty falls back to the registered dsh:// protocol. */
  executablePath?: string;
  /** How long the helper may wait for a window after launching the app. */
  waitMs?: number;
}

const LOCAL_APP_DATA =
  process.env.LOCALAPPDATA?.trim() || join(homedir(), "AppData", "Local");

/** Compiled helper the bootstrap script caches; running it directly skips PowerShell startup. */
const HELPER_EXECUTABLE = join(LOCAL_APP_DATA, "RaycastDsh", "dsh-window.exe");

/**
 * Locate the shipped bootstrap script.
 *
 * `environment.assetsPath` points at the installed `assets` directory, which is where the build
 * copies the script. The second candidate covers a host that flattens that directory.
 */
function findHelperScript(): string | undefined {
  return [
    join(environment.assetsPath, "scripts", "dsh-window.ps1"),
    join(environment.assetsPath, "dsh-window.ps1"),
  ].find((candidate) => existsSync(candidate));
}

/**
 * Whether the cached binary can be trusted over the shipped script.
 *
 * The script owns the cache and recompiles whenever its embedded source changes, so a binary older
 * than the script is stale and has to be rebuilt by going through the script once more. Without a
 * script to compare against, an existing binary is the only thing left to run.
 */
function cachedHelperIsCurrent(script: string | undefined): boolean {
  if (!existsSync(HELPER_EXECUTABLE)) return false;
  if (script === undefined) return true;
  try {
    return statSync(HELPER_EXECUTABLE).mtimeMs >= statSync(script).mtimeMs;
  } catch {
    return true;
  }
}

/**
 * Ask the helper to perform one window action.
 *
 * The compiled helper is preferred because it answers in about 100 ms, where starting
 * Windows PowerShell costs roughly half a second. The script is always available as a
 * fallback: it compiles the helper, so the next call takes the fast path.
 */
export async function runWindowAction(
  action: WindowAction,
  request: WindowRequest,
): Promise<WindowReport> {
  const waitMs = Math.max(0, Math.trunc(request.waitMs ?? 0));
  const timeoutMs = waitMs + 20_000;
  const script = findHelperScript();

  if (cachedHelperIsCurrent(script)) {
    const report = await invoke(
      HELPER_EXECUTABLE,
      [
        action,
        request.processName,
        request.executablePath ?? "",
        String(waitMs),
      ],
      timeoutMs,
    );
    if (report) return report;
  }

  if (script === undefined) {
    throw new Error(
      `The DSH window helper script is missing from ${environment.assetsPath}. Reinstall the extension.`,
    );
  }

  const report = await invoke(
    "powershell.exe",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      script,
      "-Action",
      action,
      "-ProcessName",
      request.processName,
      "-ExecutablePath",
      request.executablePath ?? "",
      "-WaitMs",
      String(waitMs),
    ],
    timeoutMs,
  );
  if (report) return report;

  throw new Error(
    "The DeepSeek Harness window helper produced no usable output.",
  );
}

/**
 * Run one helper process.
 *
 * Resolves with the parsed report whenever the helper answered, including when it reported a
 * failure — those are results, not transport errors. Resolves with null only when the command
 * itself is unavailable, which lets the caller fall back to the script. Rejects on a timeout.
 */
function invoke(
  command: string,
  args: string[],
  timeoutMs: number,
): Promise<WindowReport | null> {
  return new Promise((resolve, reject) => {
    execFile(
      command,
      args,
      {
        windowsHide: true,
        timeout: timeoutMs,
        maxBuffer: 1024 * 1024,
        encoding: "utf8",
      },
      (error, stdout, stderr) => {
        if (error && (error as NodeJS.ErrnoException).code === "ENOENT") {
          resolve(null);
          return;
        }
        if (error && (error as { killed?: boolean }).killed) {
          reject(
            new Error(
              `The window helper did not finish within ${Math.round(timeoutMs / 1000)} seconds.`,
            ),
          );
          return;
        }

        const report = parseReport(stdout) ?? parseReport(stderr);
        if (report) {
          resolve(report);
          return;
        }
        if (error) {
          reject(new Error(stderr.trim() || error.message));
          return;
        }
        resolve(null);
      },
    );
  });
}

/** Read the helper's JSON object out of a stream that may carry banners around it. */
function parseReport(text: string): WindowReport | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  let raw: Record<string, unknown>;
  try {
    raw = JSON.parse(text.slice(start, end + 1)) as Record<string, unknown>;
  } catch {
    return null;
  }
  if (typeof raw.ok !== "boolean") return null;
  return {
    ok: raw.ok,
    action: asString(raw.action),
    result: asResult(raw.result),
    state: asState(raw.state),
    running: raw.running === true,
    processCount: asNumber(raw.processCount),
    processId: asNumber(raw.processId),
    hasWindow: raw.hasWindow === true,
    hwnd: asString(raw.hwnd),
    visible: raw.visible === true,
    minimized: raw.minimized === true,
    foreground: raw.foreground === true,
    inFront: raw.inFront === true,
    title: asString(raw.title),
    executable: asString(raw.executable),
    message: asString(raw.message),
  };
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function asResult(value: unknown): WindowResult {
  const allowed: WindowResult[] = [
    "reported",
    "shown",
    "hidden",
    "launched",
    "noop",
  ];
  return allowed.includes(value as WindowResult)
    ? (value as WindowResult)
    : "reported";
}

function asState(value: unknown): WindowStateName {
  const allowed: WindowStateName[] = [
    "not-running",
    "no-window",
    "hidden",
    "minimized",
    "visible",
    "active",
  ];
  return allowed.includes(value as WindowStateName)
    ? (value as WindowStateName)
    : "not-running";
}
