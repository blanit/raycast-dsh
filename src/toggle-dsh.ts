import { performWindowAction } from "./lib/command";

/**
 * Hide the DSH window while it is the active window; otherwise reveal and focus it.
 *
 * This is the command to bind to a global hotkey. It reads the window's real Win32 state, so a
 * hidden, minimized or background window is always brought forward before the next press hides it.
 */
export default async function ToggleDsh() {
  await performWindowAction("toggle");
}
