import { createTestRenderer } from "@opentui/core/testing";
import { Result$Ok, Result$Error } from "./gleam.mjs";
const call = fn => (...args) => {
  try { return Result$Ok(fn(...args)); }
  catch (error) { return Result$Error(String(error)); }
};
const asyncCall = fn => async (...args) => {
  try { return Result$Ok(await fn(...args)); }
  catch (error) { return Result$Error(String(error)); }
};
export const create = asyncCall(options => createTestRenderer(JSON.parse(options)));
export const renderer = setup => setup.renderer;
export const input = setup => setup.mockInput;
export const mouse = setup => setup.mockMouse;
export const click = asyncCall((mouse, x, y) => mouse.click(x, y));
export const renderOnce = asyncCall(setup => setup.renderOnce());
export const capture = setup => setup.captureCharFrame();
export const resize = call((setup, width, height) => setup.resize(width, height));
export const typeText = asyncCall((input, text) => input.typeText(text));
export const pressKey = call((input, key, ctrl, shift, meta) => input.pressKey(key, { ctrl, shift, meta }));
export const paste = asyncCall((input, text) => input.pasteBracketedText(text));
