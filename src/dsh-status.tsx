import { Action, ActionPanel, Icon, List, open, Keyboard } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";

import { performWindowAction } from "./lib/command";
import { readHarnessHome, type HarnessHome } from "./lib/harness-home";
import { readSettings } from "./lib/preferences";
import {
  runWindowAction,
  type WindowAction,
  type WindowReport,
} from "./lib/window-control";

interface Snapshot {
  report: WindowReport;
  home: HarnessHome;
}

export default function DshStatus() {
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [failure, setFailure] = useState<string>();

  const refresh = useCallback(async () => {
    const settings = readSettings();
    try {
      const report = await runWindowAction("status", {
        processName: settings.processName,
        executablePath: settings.executablePath,
      });
      setSnapshot({ report, home: readHarnessHome() });
      setFailure(undefined);
    } catch (error) {
      setFailure(error instanceof Error ? error.message : String(error));
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const perform = useCallback(
    async (action: WindowAction) => {
      await performWindowAction(action);
      await refresh();
    },
    [refresh],
  );

  if (failure !== undefined) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.Warning}
          title="The DSH window helper could not run"
          description={failure}
          actions={
            <ActionPanel>
              <Action
                title="Refresh"
                icon={Icon.ArrowClockwise}
                onAction={refresh}
              />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  const report = snapshot?.report;
  const home = snapshot?.home;
  const actions = (
    <DshActions onPerform={perform} onRefresh={refresh} home={home} />
  );

  return (
    <List
      isLoading={snapshot === undefined}
      searchBarPlaceholder="Filter DSH details"
    >
      <List.Section title="Window">
        <List.Item
          icon={windowIcon(report)}
          title={windowTitle(report)}
          subtitle={report?.title || undefined}
          accessories={
            report?.hasWindow
              ? [
                  { text: `${report.inFront ? "in front" : "not in front"}` },
                  { text: `pid ${report.processId}` },
                ]
              : []
          }
          actions={actions}
        />
        <List.Item
          icon={Icon.Terminal}
          title={
            report?.running
              ? "Desktop shell running"
              : "Desktop shell not running"
          }
          subtitle={
            report
              ? `${report.processCount} processes share the shell image name`
              : undefined
          }
          accessories={
            report?.running ? [{ text: `pid ${report.processId}` }] : []
          }
          actions={actions}
        />
      </List.Section>

      <List.Section title="Installation">
        <List.Item
          icon={Icon.AppWindow}
          title={report?.executable || "Executable not detected"}
          subtitle="Used when a command has to launch DSH"
          actions={actions}
        />
        <List.Item
          icon={Icon.Folder}
          title={home?.path ?? "Locating harness home"}
          subtitle={
            home
              ? `${home.profiles.length} profiles · ${home.sessions} sessions across ${home.workspaces} workspaces`
              : undefined
          }
          actions={actions}
        />
        {home && home.profiles.length > 0 ? (
          <List.Item
            icon={Icon.Gear}
            title="Profiles"
            subtitle={home.profiles.join(", ")}
            actions={actions}
          />
        ) : null}
      </List.Section>
    </List>
  );
}

function DshActions(props: {
  onPerform: (action: WindowAction) => void;
  onRefresh: () => void;
  home?: HarnessHome;
}) {
  const homePath = props.home?.exists ? props.home.path : undefined;
  return (
    <ActionPanel>
      <Action
        title="Toggle Window"
        icon={Icon.Switch}
        onAction={() => props.onPerform("toggle")}
      />
      <Action
        title="Show Window"
        icon={Icon.Eye}
        onAction={() => props.onPerform("show")}
      />
      <Action
        title="Hide Window"
        icon={Icon.EyeDisabled}
        onAction={() => props.onPerform("hide")}
      />
      <ActionPanel.Section>
        <Action
          title="Refresh"
          icon={Icon.ArrowClockwise}
          shortcut={Keyboard.Shortcut.Common.Refresh}
          onAction={props.onRefresh}
        />
        {homePath !== undefined ? (
          <Action
            title="Open Harness Home"
            icon={Icon.Folder}
            onAction={() => open(homePath)}
          />
        ) : null}
      </ActionPanel.Section>
    </ActionPanel>
  );
}

function windowTitle(report?: WindowReport): string {
  switch (report?.state) {
    case "active":
      return "Active and focused";
    case "visible":
      return "Visible behind other windows";
    case "minimized":
      return "Minimized";
    case "hidden":
      return "Hidden to the notification area";
    case "no-window":
      return "Running without a window";
    case "not-running":
      return "Not running";
    default:
      return "Loading";
  }
}

function windowIcon(report?: WindowReport): Icon {
  switch (report?.state) {
    case "active":
    case "visible":
      return Icon.Eye;
    case "hidden":
      return Icon.EyeDisabled;
    case "minimized":
      return Icon.Minus;
    case "no-window":
      return Icon.Desktop;
    default:
      return Icon.XMarkCircle;
  }
}
