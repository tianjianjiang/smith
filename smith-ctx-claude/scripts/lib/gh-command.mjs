export const GH_GLOBAL_VALUE_FLAGS = new Set(["-R", "--repo", "--hostname"]);

export function nonFlagTokensAfterGh(tokens) {
  const result = [];
  for (let index = 1; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (GH_GLOBAL_VALUE_FLAGS.has(token)) {
      index += 1;
      continue;
    }
    if (token.startsWith("-")) continue;
    result.push(token);
  }
  return result;
}
