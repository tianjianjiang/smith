import assert from "node:assert/strict";
import {
  carriesProtectedString,
  identifiersFromGitListing,
  usableIdentifiers,
} from "../lib/protected-text.mjs";

const EMAIL = "someone@example.invalid";
const NAME = "Fixture Person Name";
const HOME = "/Users/fixture.person";
const { usable } = usableIdentifiers([EMAIL, NAME], HOME);

const blocked = {
  "incident-shaped curl": {
    command: `curl -sL "https://api.example.invalid/v2/10.1/x?email=${EMAIL}"`,
  },
  "percent-encoded address": { url: "https://example.invalid/?q=someone%40example.invalid" },
  "address in another letter case": { query: "SomeOne@Example.INVALID" },
  "name with plus for spaces": { url: "https://example.invalid/?q=Fixture+Person+Name" },
  "name with encoded spaces": { url: "https://example.invalid/?q=Fixture%20Person%20Name" },
  "commit author typed by the agent": {
    command: `git commit --author="${NAME} <${EMAIL}>" -m fix`,
  },
  "subagent prompt": { prompt: `Use ${EMAIL} for the polite pool.` },
  "nested value": { params: { headers: [`From: ${EMAIL}`] } },
  "object key": { fields: { [EMAIL]: true } },
  "address beside an escape that does not decode": {
    url: "https://example.invalid/?a=%ff&q=someone%40example.invalid",
  },
};
for (const [name, toolInput] of Object.entries(blocked)) {
  assert.equal(carriesProtectedString(toolInput, usable), true, name);
}

const allowed = {
  "plain commit": { command: 'git commit -m "fix: handle empty input"' },
  "path under the home directory": { file_path: `${HOME}/Projects/x/README.md` },
  "another address": { url: "https://example.invalid/?email=other@example.invalid" },
  "empty input": {},
  "no input": undefined,
};
for (const [name, toolInput] of Object.entries(allowed)) {
  assert.equal(carriesProtectedString(toolInput, usable), false, name);
}

assert.deepEqual(
  usableIdentifiers([EMAIL, ` ${EMAIL.toUpperCase()} `, "abc", "fixture.person", "", "  "], HOME),
  { usable: [EMAIL], skipped: 2 },
  "short entries and parts of the home path are skipped, blanks and repeats dropped",
);
assert.equal(carriesProtectedString({ command: "ls" }, []), false, "no identifiers");

const QUOTED_NAME = 'Fixture "Nick" Person\\Name';
assert.equal(
  carriesProtectedString(
    { content: `signed, ${QUOTED_NAME}` },
    usableIdentifiers([QUOTED_NAME], HOME).usable,
  ),
  true,
  "a protected string holding a quote and a backslash",
);

assert.deepEqual(
  identifiersFromGitListing(
    `user.email ${EMAIL}\nuser.name ${NAME}\nuser.name\n`,
  ),
  [EMAIL, NAME],
  "a value keeps its spaces, and a key without a value yields nothing",
);

console.log("PASS: protected-text");
