import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";

export function hasBlockType(content, type) {
  return Array.isArray(content) && content.some((block) => block && block.type === type);
}

export function toolUseNames(content) {
  if (!Array.isArray(content)) return [];
  return content.filter((block) => block && block.type === "tool_use").map((block) => block.name);
}

export function isGenuineNewUserTurn(event) {
  if (!event || event.type !== "user" || event.isMeta === true) return false;
  const content = event.message && event.message.content;
  return !hasBlockType(content, "tool_result");
}

export async function* readTranscriptEvents(transcriptPath) {
  const lines = createInterface({
    input: createReadStream(transcriptPath, { encoding: "utf-8" }),
    crlfDelay: Infinity,
  });
  for await (const line of lines) {
    if (!line.trim()) continue;
    try {
      yield JSON.parse(line);
    } catch {
      continue;
    }
  }
}

function assistantMessageId(event) {
  return event && event.type === "assistant" && event.message && typeof event.message.id === "string"
    ? event.message.id
    : null;
}

function contentBlocks(event) {
  return Array.isArray(event.message.content) ? [...event.message.content] : [];
}

export async function* readTranscriptTurns(transcriptPath) {
  let buffered = null;

  for await (const event of readTranscriptEvents(transcriptPath)) {
    const id = assistantMessageId(event);
    if (buffered && buffered.message.id === id) {
      buffered.message.content.push(...contentBlocks(event));
      continue;
    }

    if (buffered) yield buffered;
    if (id === null) {
      buffered = null;
      yield event;
      continue;
    }
    buffered = {
      type: "assistant",
      isSidechain: event.isSidechain === true,
      message: { id, content: contentBlocks(event) },
    };
  }
  if (buffered) yield buffered;
}
