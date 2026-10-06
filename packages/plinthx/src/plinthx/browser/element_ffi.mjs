import { Result$Ok, Result$Error } from "../../gleam.mjs";

export function contentWindow(element) {
  const contentWindow = element.contentWindow;
  return contentWindow != null ? Result$Ok(contentWindow) : Result$Error(undefined);
}
