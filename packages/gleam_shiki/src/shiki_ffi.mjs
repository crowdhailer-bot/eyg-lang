import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import githubDark from "shiki/themes/github-dark.mjs";
import { Result$Ok, Result$Error } from "./gleam.mjs";

export async function create(grammar) {
  try {
    return Result$Ok(await createHighlighterCore({
      langs: [JSON.parse(grammar)], themes: [githubDark], engine: createJavaScriptRegexEngine(),
    }));
  } catch (error) { return Result$Error(String(error)); }
}
export function tokens(highlighter, source, language, theme) {
  try { return Result$Ok(highlighter.codeToTokens(source, { lang: language, theme })); }
  catch (error) { return Result$Error(String(error)); }
}
