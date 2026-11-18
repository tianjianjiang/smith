#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const KEY_SHAPED_PATTERN = /sk-ant-[A-Za-z0-9_-]{20,}/g;
const KEY_SHAPED_MINIMUM_LENGTH = 'sk-ant-'.length + 20;
const MARKER_NAME = 'LEAK-FOUND';
const MARKER_TEXT = 'A leak scan found secret material in this folder.\nRevoke the key in the vendor console, then read the scan report.\n';
const REVOKE_INSTRUCTION = 'Revoke the exposed key in the vendor console before any other step.';
const USAGE = 'usage: behaviour-eval-leak-scan.mjs --report FILE ROOT...  (needles, one per line, on stdin)';
const READ_CHUNK_BYTES = 1 << 20;
const BASE64_LEADING_BYTES = [0, 1, 2];
const EXIT_CLEAN = 0;
const EXIT_FOUND = 1;
const EXIT_USAGE = 2;
const EXIT_NOT_RUN = 3;

function parseArguments(args) {
  let reportPath = null;
  const roots = [];
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--report') {
      index++;
      reportPath = args[index] ?? null;
    } else if (args[index].startsWith('--')) {
      return null;
    } else {
      roots.push(args[index]);
    }
  }
  return reportPath && roots.length > 0 ? { reportPath, roots } : null;
}

function readStdinBytes() {
  try {
    return fs.readFileSync(0);
  } catch {
    return Buffer.alloc(0);
  }
}

function splitNeedles(bytes) {
  const needles = new Map();
  let lineStart = 0;
  for (let index = 0; index <= bytes.length; index++) {
    if (index === bytes.length || bytes[index] === 0x0a) {
      let lineEnd = index;
      if (lineEnd > lineStart && bytes[lineEnd - 1] === 0x0d) lineEnd--;
      if (lineEnd > lineStart) {
        const needle = Buffer.from(bytes.subarray(lineStart, lineEnd));
        needles.set(needle.toString('hex'), needle);
      }
      lineStart = index + 1;
    }
  }
  return [...needles.values()];
}

function jsonEscapedBytes(needle) {
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(needle);
    return Buffer.from(JSON.stringify(text).slice(1, -1));
  } catch {
    return null;
  }
}

function base64Texts(needle, leadingBytes) {
  const encoded = Buffer.concat([Buffer.alloc(leadingBytes), needle]).toString('base64').replace(/=+$/, '');
  const firstOwnChar = Math.ceil((8 * leadingBytes) / 6);
  const endOwnChar = Math.floor((8 * (leadingBytes + needle.length)) / 6);
  const standard = encoded.slice(firstOwnChar, endOwnChar);
  const urlSafe = standard.replaceAll('+', '-').replaceAll('/', '_');
  return [standard, urlSafe];
}

function patternsForNeedle(needle) {
  const patterns = [{ form: 'raw', bytes: needle }];
  const escaped = jsonEscapedBytes(needle);
  if (escaped && !escaped.equals(needle)) patterns.push({ form: 'json-escaped', bytes: escaped });
  for (const leadingBytes of BASE64_LEADING_BYTES) {
    for (const text of base64Texts(needle, leadingBytes)) {
      patterns.push({ form: 'base64', bytes: Buffer.from(text, 'latin1') });
    }
  }
  return patterns;
}

function uniquePatterns(patterns) {
  const byIdentity = new Map();
  for (const pattern of patterns) {
    if (pattern.bytes.length > 0) byIdentity.set(`${pattern.form} ${pattern.bytes.toString('hex')}`, pattern);
  }
  return [...byIdentity.values()];
}

function collectFixedHits(window, windowStart, decidedEnd, patterns, hits) {
  for (const { form, bytes } of patterns) {
    for (let at = window.indexOf(bytes); at !== -1; at = window.indexOf(bytes, at + 1)) {
      const offset = windowStart + at;
      if (offset + bytes.length > decidedEnd) hits.set(`${offset} ${form}`, { offset, form });
    }
  }
}

function collectKeyHits(window, windowStart, decidedEnd, atEnd, hits) {
  const text = window.toString('latin1');
  let openStart = null;
  for (const match of text.matchAll(KEY_SHAPED_PATTERN)) {
    const end = match.index + match[0].length;
    if (!atEnd && end === text.length) {
      openStart = windowStart + match.index;
    } else if (windowStart + end > decidedEnd) {
      const offset = windowStart + match.index;
      hits.set(`${offset} key-shaped`, { offset, form: 'key-shaped' });
    }
  }
  return openStart;
}

function scanFile(filePath, patterns) {
  const hits = new Map();
  const longestPattern = Math.max(KEY_SHAPED_MINIMUM_LENGTH, ...patterns.map((pattern) => pattern.bytes.length));
  const carryLength = longestPattern - 1;
  const chunk = Buffer.allocUnsafe(Math.max(READ_CHUNK_BYTES, 2 * longestPattern));
  const descriptor = fs.openSync(filePath, 'r');
  try {
    let carry = Buffer.alloc(0);
    let consumed = 0;
    let fixedDecidedEnd = 0;
    let keyDecidedEnd = 0;
    for (;;) {
      const bytesRead = fs.readSync(descriptor, chunk, 0, chunk.length, null);
      const atEnd = bytesRead === 0;
      const window = Buffer.concat([carry, chunk.subarray(0, bytesRead)]);
      const windowStart = consumed - carry.length;
      collectFixedHits(window, windowStart, fixedDecidedEnd, patterns, hits);
      const openKeyStart = collectKeyHits(window, windowStart, keyDecidedEnd, atEnd, hits);
      consumed += bytesRead;
      fixedDecidedEnd = consumed;
      keyDecidedEnd = openKeyStart ?? consumed;
      if (atEnd) break;
      const keepFrom = Math.max(0, window.length - carryLength);
      carry = window.subarray(openKeyStart === null ? keepFrom : Math.min(keepFrom, openKeyStart - windowStart));
    }
  } finally {
    fs.closeSync(descriptor);
  }
  return [...hits.values()].sort((a, b) => a.offset - b.offset || a.form.localeCompare(b.form));
}

function printable(text) {
  return text.replace(/[\u0000-\u001f\u007f]/g, '?');
}

function isInside(target, rootRealPath) {
  return target === rootRealPath || target.startsWith(rootRealPath + path.sep);
}

function describeStat(stat, entryPath) {
  if (stat.isFile()) return { kind: 'file' };
  if (stat.isDirectory()) return { kind: 'directory', realPath: fs.realpathSync(entryPath) };
  return { kind: 'skip', reason: 'not-regular-file' };
}

function classifyEntry(entryPath, rootRealPath) {
  const linkStat = fs.lstatSync(entryPath);
  if (!linkStat.isSymbolicLink()) return describeStat(linkStat, entryPath);
  let target;
  try {
    target = fs.realpathSync(entryPath);
  } catch {
    return { kind: 'skip', reason: 'broken-link' };
  }
  if (!isInside(target, rootRealPath)) return { kind: 'skip', reason: 'leaves-root' };
  return describeStat(fs.statSync(entryPath), entryPath);
}

function markUnreadable(root, relativePath) {
  root.unreadable.push(printable(relativePath));
  root.lines.push(`${printable(relativePath)}\tnot-scanned\tunreadable`);
}

function scanRegularFile(root, filePath, relativePath) {
  let hits;
  try {
    hits = scanFile(filePath, root.patterns);
  } catch {
    markUnreadable(root, relativePath);
    return;
  }
  root.filesRead = true;
  for (const { form, offset } of hits) {
    root.lines.push(`${printable(relativePath)}\t${form}\t${offset}`);
    root.hit = true;
  }
}

function visitEntry(root, entryPath, ancestors) {
  const relativePath = path.relative(root.realPath, entryPath);
  let entry;
  try {
    entry = classifyEntry(entryPath, root.realPath);
  } catch {
    markUnreadable(root, relativePath);
    return;
  }
  if (entry.kind === 'skip') {
    root.lines.push(`${printable(relativePath)}\tnot-scanned\t${entry.reason}`);
  } else if (entry.kind === 'directory' && ancestors.has(entry.realPath)) {
    root.lines.push(`${printable(relativePath)}\tnot-scanned\tloop`);
  } else if (entry.kind === 'directory') {
    walkDirectory(root, entryPath, new Set(ancestors).add(entry.realPath));
  } else {
    scanRegularFile(root, entryPath, relativePath);
  }
}

function walkDirectory(root, directoryPath, ancestors) {
  let names;
  try {
    names = fs.readdirSync(directoryPath).sort();
  } catch {
    markUnreadable(root, path.relative(root.realPath, directoryPath) || '.');
    return;
  }
  for (const name of names) visitEntry(root, path.join(directoryPath, name), ancestors);
}

function scanRoot(argument, realPath, patterns) {
  const root = { argument, realPath, patterns, lines: [], unreadable: [], filesRead: false, hit: false };
  walkDirectory(root, realPath, new Set([realPath]));
  return root;
}

function resolveFolder(argument) {
  try {
    const realPath = fs.realpathSync(argument);
    return fs.statSync(realPath).isDirectory() ? realPath : null;
  } catch {
    return null;
  }
}

function reasonsScanDidNotComplete(roots) {
  return roots.flatMap((root) => [
    ...(root.filesRead ? [] : [`root holds no file: ${printable(root.argument)}`]),
    ...root.unreadable.map((relativePath) => `unreadable: ${relativePath} in ${printable(root.argument)}`),
  ]);
}

function renderReport(roots, notRunReasons) {
  const filesRead = roots.some((root) => root.filesRead);
  const sections = roots.flatMap((root) => [`root: ${printable(root.argument)}`, ...root.lines]);
  const reasons = notRunReasons.map((reason) => `not-run: ${reason}`);
  return [...sections, `files-read: ${filesRead ? 'yes' : 'no'}`, ...reasons].join('\n') + '\n';
}

function writeReport(reportPath, text) {
  try {
    fs.writeFileSync(reportPath, text, { mode: 0o600 });
    return true;
  } catch (error) {
    process.stderr.write(`could not write the report: ${error.code ?? 'unknown error'}\n`);
    return false;
  }
}

function writeMarker(rootPath) {
  const flags = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL;
  const descriptor = fs.openSync(path.join(rootPath, MARKER_NAME), flags, 0o600);
  try {
    fs.writeSync(descriptor, MARKER_TEXT);
  } finally {
    fs.closeSync(descriptor);
  }
}

function quarantine(root) {
  try {
    writeMarker(root.realPath);
  } catch (error) {
    if (error.code !== 'EEXIST') process.stderr.write(`could not write the marker: ${error.code ?? 'unknown error'}\n`);
  }
  try {
    fs.chmodSync(root.realPath, 0o700);
  } catch (error) {
    process.stderr.write(`could not restrict the folder: ${error.code ?? 'unknown error'}\n`);
  }
}

function reportNotRun(reasons) {
  for (const reason of reasons) process.stderr.write(`Scan not run: ${reason}\n`);
  return EXIT_NOT_RUN;
}

function reportFound(roots, reportPath, incompleteReasons) {
  const hitRoots = roots.filter((root) => root.hit);
  hitRoots.forEach(quarantine);
  process.stdout.write(`Leak found. Report: ${reportPath}\n`);
  for (const root of hitRoots) process.stdout.write(`Quarantined in place (marker and owner-only mode): ${root.realPath}\n`);
  for (const reason of incompleteReasons) process.stdout.write(`Scan incomplete: ${reason}\n`);
  process.stdout.write(`${REVOKE_INSTRUCTION}\n`);
  return EXIT_FOUND;
}

function run(args) {
  const parsed = parseArguments(args);
  if (!parsed) {
    process.stderr.write(`${USAGE}\n`);
    return EXIT_USAGE;
  }
  const needles = splitNeedles(readStdinBytes());
  const resolvedRoots = parsed.roots.map((argument) => ({ argument, realPath: resolveFolder(argument) }));
  const preflightReasons = [
    ...(needles.length === 0 ? ['no needle on stdin'] : []),
    ...resolvedRoots.filter((root) => !root.realPath).map((root) => `root missing or not a folder: ${printable(root.argument)}`),
  ];
  if (preflightReasons.length > 0) {
    writeReport(parsed.reportPath, renderReport([], preflightReasons));
    return reportNotRun(preflightReasons);
  }
  const patterns = uniquePatterns(needles.flatMap(patternsForNeedle));
  const roots = resolvedRoots.map((root) => scanRoot(root.argument, root.realPath, patterns));
  const incompleteReasons = reasonsScanDidNotComplete(roots);
  const reportWritten = writeReport(parsed.reportPath, renderReport(roots, incompleteReasons));
  if (roots.some((root) => root.hit)) return reportFound(roots, parsed.reportPath, incompleteReasons);
  if (!reportWritten) return EXIT_NOT_RUN;
  if (incompleteReasons.length > 0) return reportNotRun(incompleteReasons);
  process.stdout.write(`No leak found. Report: ${parsed.reportPath}\n`);
  return EXIT_CLEAN;
}

try {
  process.exitCode = run(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`Scan failed: ${error?.code ?? 'internal error'}\n`);
  process.exitCode = EXIT_NOT_RUN;
}
