import { Some, None } from "../../../gleam_stdlib/gleam/option.mjs";
import { Call, Bind, Handle, Perform, Resume } from "./runtime.mjs";
export const step = value =>
  value instanceof Call || value instanceof Bind || value instanceof Handle ||
  value instanceof Perform || value instanceof Resume
    ? new Some(value) : new None();
