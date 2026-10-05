import { performWindowAction } from "./lib/command";

/** Reveal, restore and focus the DSH window, launching the desktop app when it is not running. */
export default async function ShowDsh() {
  await performWindowAction("show");
}
