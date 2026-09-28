export const MINIMUM_IDENTIFIER_LENGTH = 4;

function percentDecoded(text) {
  return text.replace(/(%[0-9a-f]{2})+/gi, (run) => {
    try {
      return decodeURIComponent(run);
    } catch {
      return run;
    }
  });
}

function normalized(text) {
  return percentDecoded(text).toLowerCase();
}

export function usableIdentifiers(entries, homeDirectory) {
  const home = normalized(homeDirectory);
  const distinct = [
    ...new Set(entries.map((entry) => normalized(entry.trim())).filter(Boolean)),
  ];
  const usable = distinct.filter(
    (identifier) =>
      identifier.length >= MINIMUM_IDENTIFIER_LENGTH &&
      !home.includes(identifier),
  );
  return { usable, skipped: distinct.length - usable.length };
}

export function identifiersFromGitListing(listing) {
  return listing
    .split("\n")
    .filter((line) => line.includes(" "))
    .map((line) => line.slice(line.indexOf(" ") + 1));
}

function asJsonSpellsIt(identifier) {
  return JSON.stringify(identifier).slice(1, -1);
}

export function carriesProtectedString(toolInput, identifiers) {
  const text = normalized(JSON.stringify(toolInput) ?? "");
  const readings = [text, text.replace(/\+/g, " ")];
  return identifiers.some((identifier) =>
    readings.some((reading) => reading.includes(asJsonSpellsIt(identifier))),
  );
}
