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
