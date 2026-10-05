/**
 * Timing probe: run one helper action and watch the real window state settle afterwards.
 *
 * Usage: node _tools/probe-timing.cjs <action> [--via node|powershell] [--samples 12]
 */

const { execFile } = require("node:child_process");
const path = require("node:path");

const helperExe = path.join(process.env.LOCALAPPDATA, "RaycastDsh", "dsh-window.exe");
const helperScript = path.join(__dirname, "..", "assets", "scripts", "dsh-window.ps1");

const action = process.argv[2] ?? "show";
const viaIndex = process.argv.indexOf("--via");
const via = viaIndex > -1 ? process.argv[viaIndex + 1] : "node";
const samplesIndex = process.argv.indexOf("--samples");
const samples = samplesIndex > -1 ? Number.parseInt(process.argv[samplesIndex + 1], 10) : 12;

const command = via === "powershell" ? "powershell.exe" : helperExe;
const argsFor = (step) =>
  via === "powershell"
    ? ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helperScript, "-Action", step, "-ProcessName", "DeepSeek Harness"]
    : [step, "DeepSeek Harness", "", "0"];

function run(step) {
  return new Promise((resolve) => {
    execFile(command, argsFor(step), { windowsHide: true, encoding: "utf8", timeout: 30000 }, (error, stdout, stderr) => {
      resolve({ error: error?.message, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function summarise(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) return text;
  const parsed = JSON.parse(text.slice(start, end + 1));
  return `result=${parsed.result} state=${parsed.state} visible=${parsed.visible} foreground=${parsed.foreground}`;
}

async function main() {
  console.log(`via=${via} action=${action}`);
  console.log(`  before: ${summarise((await run("status")).stdout)}`);
  console.log(`  ${action}: ${summarise((await run(action)).stdout)}`);
  for (let index = 1; index <= samples; index++) {
    await delay(250);
    console.log(`  +${index * 250}ms: ${summarise((await run("status")).stdout)}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
