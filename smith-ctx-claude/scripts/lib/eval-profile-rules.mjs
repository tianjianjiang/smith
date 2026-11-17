import { join, relative } from "node:path";
import { canonicalPath, isInside } from "../../../smith-git/scripts/lib/serena-root.mjs";

const NOT_FOLLOWED_BY_A_NAME_CHARACTER = "(?![\\w.-])";
const NOT_PRECEDED_BY_A_PATH_CHARACTER = "(?<![\\w./])";
const HOME_VARIABLE = "\"?(?:\\$HOME|\\$\\{HOME(?::?-[^}]*)?\\})\"?";
const MAY_CHANGE_CLAUDE_CONFIG_DIR = /(?<![\w.-])(?:env|unset)(?![\w./-])|(?<!\$\{)\bCLAUDE_CONFIG_DIR\b/;
const UNUSED_CONFIG_FOLDER_DEFAULT = /\$\{CLAUDE_CONFIG_DIR:?-[^}]*\}/g;

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function evalConfigFolderIsUsable({ home, evalConfigFolder }) {
  const [realHome, realEvalFolder] = [canonicalPath(home), canonicalPath(evalConfigFolder)];
  const isHomeOrAbove = isInside(realEvalFolder, realHome);
  const isInTheDefaultProfile = isInside(canonicalPath(join(home, ".claude")), realEvalFolder);
  return !isHomeOrAbove && !isInTheDefaultProfile;
}

function pathBelowHome(home, folder) {
  return isInside(home, folder) ? relative(home, folder) || undefined : undefined;
}

function homePrefixes(home) {
  return `${NOT_PRECEDED_BY_A_PATH_CHARACTER}(/?${escapeRegExp(home)}|~|${HOME_VARIABLE})`;
}

function writesTheDoubleSlashPathForm(prefix, rule) {
  if (prefix.startsWith("/")) return prefix.startsWith("//");
  return !rule.startsWith("Bash(");
}

function evalFolderOutsideHome(prefix, rule, evalConfigFolder) {
  const folder = writesTheDoubleSlashPathForm(prefix, rule) ? `/${evalConfigFolder}` : evalConfigFolder;
  const openingQuote = prefix.startsWith("\"") ? "\"" : "";
  const closingQuote = prefix.length > 1 && prefix.endsWith("\"") ? "\"" : "";
  return `${openingQuote}${folder}${closingQuote}`;
}

export function evalPermissionRule(rule, { home, evalConfigFolder }) {
  const userConfigFolder = new RegExp(`${homePrefixes(home)}/\\.claude${NOT_FOLLOWED_BY_A_NAME_CHARACTER}`, "g");
  const evalFolderFromHome = pathBelowHome(home, evalConfigFolder);
  return rule.replace(userConfigFolder, (_, prefix) => evalFolderFromHome
    ? `${prefix}/${evalFolderFromHome}`
    : evalFolderOutsideHome(prefix, rule, evalConfigFolder));
}

export function evalDenyRules(rules, folders) {
  return [...new Set(rules.flatMap((rule) => [rule, evalPermissionRule(rule, folders)]))];
}

export function namesAnInstalledCopy(text, home) {
  const installedCopy = new RegExp(`${homePrefixes(home)}/(\\.claude|\\.smith)${NOT_FOLLOWED_BY_A_NAME_CHARACTER}`);
  const readText = MAY_CHANGE_CLAUDE_CONFIG_DIR.test(text) ? text : text.replace(UNUSED_CONFIG_FOLDER_DEFAULT, "${CLAUDE_CONFIG_DIR}");
  return installedCopy.test(readText);
}
