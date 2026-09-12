import {
  Action,
  ActionPanel,
  Alert,
  confirmAlert,
  Detail,
  getPreferenceValues,
  Icon,
  List,
  openExtensionPreferences,
  showToast,
  Toast,
} from "@raycast/api";
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { basename } from "node:path";
import { useEffect, useRef, useState } from "react";
import type { Event, Message, OpencodeClient, Part, TextPart } from "@opencode-ai/sdk";
import { ensureServer, expandHome, findOpencode } from "./lib/opencode";

type ChatMessage = { id: string; role: string; parts: Part[] };

function partMarkdown(part: Part): string {
  switch (part.type) {
    case "text":
      return part.text;
    case "reasoning":
      return `> *${part.text.replace(/\n/g, "\n> ")}*`;
    case "tool": {
      const s = part.state;
      if (s.status === "completed")
        return `\n\n**\`${part.tool}\`** ${s.title}\n\n\`\`\`\n${s.output.slice(0, 2000)}\n\`\`\``;
      if (s.status === "error")
        return `\n\n**\`${part.tool}\`** failed: ${s.error.slice(0, 500)}`;
      return `\n\n**\`${part.tool}\`** ${s.status}…`;
    }
    case "file":
      return `\`${part.filename ?? ""}\``;
    case "agent":
      return `@${part.name}`;
    default:
      return "";
  }
}

function messageMarkdown(m: ChatMessage): string {
  const body = m.parts.map(partMarkdown).filter(Boolean).join("\n\n");
  return body || "*(no content)*";
}

function preview(m: ChatMessage): string {
  const text = m.parts.find((p) => p.type === "text");
  const raw = text && "text" in text ? text.text : messageMarkdown(m);
  return raw.replace(/\s+/g, " ").trim().slice(0, 80) || "…";
}

export default function ChatCommand() {
  const prefs = getPreferenceValues<Preferences.Chat>();
  const directory = prefs.defaultDirectory ? expandHome(prefs.defaultDirectory) : "";
  if (!directory || !existsSync(directory)) {
    return (
      <Detail
        markdown={`# No project directory\n\nSet **Default Project Directory** in the extension preferences to choose where opencode works.`}
        actions={
          <ActionPanel>
            <Action title="Open Extension Preferences" onAction={openExtensionPreferences} />
          </ActionPanel>
        }
      />
    );
  }
  return <ChatView directory={directory} />;
}

export function ChatView({
  directory,
  sessionId: initialSessionId,
}: {
  directory: string;
  sessionId?: string;
}) {
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [status, setStatus] = useState<"connecting" | "ready" | "busy" | "error">("connecting");
  const [sessionId, setSessionId] = useState(initialSessionId);
  const clientRef = useRef<OpencodeClient>(null);
  const urlRef = useRef<string>("");
  const sessionRef = useRef(initialSessionId);

  function setSession(id: string | undefined) {
    sessionRef.current = id;
    setSessionId(id);
  }

  useEffect(() => {
    const ac = new AbortController();
    const upsert = (id: string, fn: (m: ChatMessage) => ChatMessage) =>
      setMessages((prev) => {
        const i = prev.findIndex((m) => m.id === id);
        if (i === -1) return [...prev, fn({ id, role: "assistant", parts: [] })];
        const next = [...prev];
        next[i] = fn(next[i]);
        return next;
      });

    (async () => {
      try {
        const { client, url } = await ensureServer(directory, ac.signal);
        clientRef.current = client;
        urlRef.current = url;
        if (sessionRef.current) {
          const res = await client.session.messages({ path: { id: sessionRef.current } });
          if (res.data)
            setMessages(
              res.data.map((m: { info: Message; parts: Part[] }) => ({
                id: m.info.id,
                role: m.info.role,
                parts: m.parts,
              })),
            );
        }
        setStatus("ready");

        const { stream } = await client.event.subscribe({ signal: ac.signal });
        for await (const event of stream) {
          if (ac.signal.aborted) break;
          handleEvent(event, upsert);
        }
      } catch (e) {
        if (!ac.signal.aborted) {
          setStatus("error");
          showToast({
            style: Toast.Style.Failure,
            title: "OpenCode error",
            message: e instanceof Error ? e.message : String(e),
          });
        }
      }
    })();
    return () => ac.abort();
  }, [directory]);

  function handleEvent(
    event: Event,
    upsert: (id: string, fn: (m: ChatMessage) => ChatMessage) => void,
  ) {
    const props = "properties" in event ? event.properties : {};
    if ("sessionID" in props && props.sessionID !== sessionRef.current) return;
    switch (event.type) {
      case "message.updated":
        if (event.properties.info.sessionID !== sessionRef.current) return;
        upsert(event.properties.info.id, (m) => ({ ...m, role: event.properties.info.role }));
        break;
      case "message.part.updated":
        upsert(event.properties.part.messageID, (m) => {
          const part = event.properties.part;
          const parts = m.parts.filter((p) => p.id !== part.id);
          return { ...m, parts: [...parts, part] };
        });
        break;
      case "session.status":
        setStatus(event.properties.status.type === "busy" ? "busy" : "ready");
        break;
      case "session.idle":
        setStatus("ready");
        break;
      case "permission.updated":
        askPermission(event.properties);
        break;
    }
  }

  async function askPermission(p: { id: string; sessionID: string; title: string }) {
    const client = clientRef.current;
    if (!client) return;
    const ok = await confirmAlert({
      title: "opencode asks permission",
      message: p.title,
      primaryAction: { title: "Allow Once" },
      dismissAction: { title: "Reject", style: Alert.ActionStyle.Destructive },
    });
    await client.postSessionIdPermissionsPermissionId({
      path: { id: p.sessionID, permissionID: p.id },
      body: { response: ok ? "once" : "reject" },
    });
  }

  async function send() {
    const client = clientRef.current;
    const text = draft.trim();
    if (!client || !text) return;
    setDraft("");
    try {
      let id = sessionRef.current;
      if (!id) {
        const res = await client.session.create({ body: { title: text.slice(0, 60) } });
        if (!res.data) throw new Error("Failed to create session");
        id = res.data.id;
        setSession(id);
      }
      const messageID = `msg_${Date.now()}`;
      const userPart: TextPart = {
        id: `${messageID}_text`,
        sessionID: id,
        messageID,
        type: "text",
        text,
      };
      setMessages((prev) => [...prev, { id: messageID, role: "user", parts: [userPart] }]);
      setStatus("busy");
      await client.session.promptAsync({
        path: { id },
        body: { parts: [{ type: "text", text }] },
      });
    } catch (e) {
      setStatus("ready");
      showToast({
        style: Toast.Style.Failure,
        title: "Send failed",
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }

  function newChat() {
    setSession(undefined);
    setMessages([]);
  }

  function openInTerminal() {
    const cmd = `cd ${JSON.stringify(directory)} && ${JSON.stringify(findOpencode())} attach ${urlRef.current}`;
    execFile("osascript", [
      "-e",
      `tell application "Terminal" to do script ${JSON.stringify(cmd)}`,
      "-e",
      `tell application "Terminal" to activate`,
    ]);
  }

  const busy = status === "busy";
  return (
    <List
      isLoading={status === "connecting" || busy}
      isShowingDetail={messages.length > 0}
      filtering={false}
      searchText={draft}
      onSearchTextChange={setDraft}
      navigationTitle={`opencode — ${basename(directory)}`}
      searchBarPlaceholder={busy ? "Working…" : "Message opencode…"}
    >
      {messages.map((m) => (
        <List.Item
          key={m.id}
          id={m.id}
          icon={m.role === "user" ? Icon.Person : Icon.Stars}
          title={preview(m)}
          detail={<List.Item.Detail markdown={messageMarkdown(m)} />}
          actions={<ChatActions busy={busy} send={send} newChat={newChat} openInTerminal={openInTerminal} sessionId={sessionId} clientRef={clientRef} />}
        />
      ))}
      <List.EmptyView
        title={status === "error" ? "Connection failed" : "Ask opencode anything"}
        description={
          status === "error"
            ? "Could not reach the opencode server"
            : `Working in ${directory}`
        }
        actions={<ChatActions busy={busy} send={send} newChat={newChat} openInTerminal={openInTerminal} sessionId={sessionId} clientRef={clientRef} />}
      />
    </List>
  );
}

function ChatActions({
  busy,
  send,
  newChat,
  openInTerminal,
  sessionId,
  clientRef,
}: {
  busy: boolean;
  send: () => void;
  newChat: () => void;
  openInTerminal: () => void;
  sessionId?: string;
  clientRef: React.RefObject<OpencodeClient | null>;
}) {
  return (
    <ActionPanel>
      <Action title="Send" icon={Icon.ArrowRight} onAction={send} />
      {busy && sessionId && (
        <Action
          title="Stop"
          icon={Icon.Stop}
          style={Action.Style.Destructive}
          shortcut={{ modifiers: ["cmd"], key: "." }}
          onAction={() =>
            clientRef.current?.session.abort({ path: { id: sessionId } })
          }
        />
      )}
      <Action title="New Chat" icon={Icon.Plus} shortcut={{ modifiers: ["cmd"], key: "n" }} onAction={newChat} />
      <Action title="Open in Terminal" icon={Icon.Terminal} shortcut={{ modifiers: ["cmd"], key: "o" }} onAction={openInTerminal} />
    </ActionPanel>
  );
}
