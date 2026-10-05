import { showHUD, showToast, Toast } from "@raycast/api";

import { readSettings } from "./preferences";
import {
  runWindowAction,
  type WindowAction,
  type WindowReport,
} from "./window-control";

/**
 * Run one window action with the configured preferences and report the outcome.
 *
 * Returns the helper report so a view can refresh from it, or null when the command could not
 * reach the helper at all. Failures are surfaced as a Raycast toast instead of a thrown error so
 * that a mistaken hotkey never opens an error screen.
 */
export async function performWindowAction(
  action: WindowAction,
): Promise<WindowReport | null> {
  const settings = readSettings();
  const request = {
    processName: settings.processName,
    executablePath: settings.executablePath,
    waitMs: settings.launchIfNotRunning ? settings.launchTimeoutMs : 0,
  };

  try {
    if (!settings.launchIfNotRunning) {
      const current = await runWindowAction("status", {
        ...request,
        waitMs: 0,
      });
      if (!current.running) {
        await showHUD("DSH is not running");
        return current;
      }
    }

    const report = await runWindowAction(action, request);
    if (!report.ok || report.result === "noop") {
      await showToast({
        style: Toast.Style.Failure,
        title: "DeepSeek Harness",
        message: report.message,
      });
      return report;
    }
    await showHUD(summarise(report));
    return report;
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "DeepSeek Harness",
      message: messageOf(error),
    });
    return null;
  }
}

/**
 * Short confirmation for the heads-up display after a successful action.
 *
 * The wording follows the state the helper observed after acting rather than the action it was
 * asked to perform, so the display never claims a focus that Windows actually refused.
 */
export function summarise(report: WindowReport): string {
  switch (report.result) {
    case "hidden":
      return "DSH window hidden";
    case "shown":
      return report.foreground ? "DSH window focused" : "DSH window shown";
    case "launched":
      return "DSH launched";
    default:
      return report.message;
  }
}

export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
