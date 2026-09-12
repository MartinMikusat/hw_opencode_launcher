import {
  Action,
  ActionPanel,
  Detail,
  getPreferenceValues,
  Icon,
  List,
  openExtensionPreferences,
  showToast,
  Toast,
} from "@raycast/api";
import { existsSync } from "node:fs";
import { useEffect, useState } from "react";
import type { Session } from "@opencode-ai/sdk";
import { ChatView } from "./chat";
import { ensureServer, expandHome } from "./lib/opencode";

export default function SessionsCommand() {
  const prefs = getPreferenceValues<Preferences.Sessions>();
  const directory = prefs.defaultDirectory ? expandHome(prefs.defaultDirectory) : "";
  const [sessions, setSessions] = useState<Session[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (!directory || !existsSync(directory)) {
      setIsLoading(false);
      return;
    }
    const ac = new AbortController();
    ensureServer(directory, ac.signal)
      .then(({ client }) => client.session.list())
      .then((res) => setSessions(res.data ?? []))
      .catch((e) => {
        setError(e instanceof Error ? e.message : String(e));
        showToast({
          style: Toast.Style.Failure,
          title: "Could not load sessions",
          message: e instanceof Error ? e.message : String(e),
        });
      })
      .finally(() => setIsLoading(false));
    return () => ac.abort();
  }, [directory]);

  if (!directory || !existsSync(directory)) {
    return (
      <Detail
        markdown={`# No project directory\n\nSet **Default Project Directory** in the extension preferences.`}
        actions={
          <ActionPanel>
            <Action title="Open Extension Preferences" onAction={openExtensionPreferences} />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <List isLoading={isLoading} navigationTitle={`Sessions — ${directory}`}>
      {sessions
        .sort((a, b) => b.time.updated - a.time.updated)
        .map((s) => (
          <List.Item
            key={s.id}
            icon={Icon.Message}
            title={s.title || "Untitled session"}
            subtitle={new Date(s.time.updated).toLocaleString()}
            accessories={s.summary ? [{ text: `+${s.summary.additions} -${s.summary.deletions}` }] : []}
            actions={
              <ActionPanel>
                <Action.Push
                  title="Open Chat"
                  icon={Icon.Message}
                  target={<ChatView directory={directory} sessionId={s.id} />}
                />
              </ActionPanel>
            }
          />
        ))}
      <List.EmptyView
        title={error ? "Could not load sessions" : "No sessions yet"}
        description={error ?? `Start one with the Chat command in ${directory}`}
      />
    </List>
  );
}
