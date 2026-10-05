import { performWindowAction } from "./lib/command";

/**
 * Hide the DSH window to the notification area.
 *
 * This is the same outcome as the shell's own close button: the process keeps running and
 * in-flight tasks are untouched, so the window can be summoned again at any time.
 */
export default async function HideDsh() {
  await performWindowAction("hide");
}
