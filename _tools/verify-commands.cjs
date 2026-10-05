/**
 * Exercise the built commands outside Raycast.
 *
 * `ray build` leaves `@raycast/api` as an external require, so the only thing standing between
 * these bundles and Node is the API surface they touch. This harness stubs exactly that surface
 * and then runs the real `dist/` entry points, which verifies the shipped code path end to end:
 * preference reading, helper invocation, output parsing and user feedback.
 *
 * Usage: node _tools/verify-commands.cjs <toggle|show|hide|status> [--asset-root <dir>]
 */

const Module = require("node:module");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const assetRootIndex = process.argv.indexOf("--asset-root");
const assetsPath = assetRootIndex > -1 ? path.resolve(process.argv[assetRootIndex + 1]) : path.join(projectRoot, "assets");

const hud = [];
const toasts = [];

const raycastStub = {
  environment: {
    assetsPath,
    supportPath: path.join(projectRoot, ".raycast"),
    extensionName: "dsh",
    commandName: "verify",
  },
  getPreferenceValues: () => ({}),
  showHUD: async (title, options) => {
    hud.push({ title, options });
  },
  showToast: async (options) => {
    toasts.push(options);
  },
  Toast: { Style: { Success: "success", Failure: "failure", Animated: "animated" } },
  confirmAlert: async () => true,
  Alert: { ActionStyle: { Destructive: "destructive", Default: "default" } },
  open: async () => undefined,
  Icon: new Proxy({}, { get: (_target, name) => String(name) }),
};

const originalLoad = Module._load;
Module._load = function patchedLoad(request, parent, isMain) {
  if (request === "@raycast/api") return raycastStub;
  return originalLoad.call(this, request, parent, isMain);
};

const entryPoints = {
  toggle: "toggle-dsh",
  show: "show-dsh",
  hide: "hide-dsh",
};

async function main() {
  const command = process.argv[2] ?? "toggle";
  if (command === "status") {
    const status = require(path.join(projectRoot, "dist", "dsh-status.js"));
    console.log(JSON.stringify({ command, exported: typeof status.default }, null, 2));
    return;
  }

  const entry = entryPoints[command];
  if (entry === undefined) throw new Error(`unknown command: ${command} (expected ${Object.keys(entryPoints).join(", ")} or status)`);

  const started = Date.now();
  const module = require(path.join(projectRoot, "dist", `${entry}.js`));
  await module.default();
  console.log(JSON.stringify({ command, elapsedMs: Date.now() - started, hud, toasts }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
