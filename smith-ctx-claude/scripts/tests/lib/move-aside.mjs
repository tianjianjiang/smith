import { mkdtempSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";

export function moveAside(path) {
  const destination = join(mkdtempSync(join(tmpdir(), "smith-moved-aside-")), basename(path));
  try {
    renameSync(path, destination);
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
  return destination;
}
