import { all_from_string, format_error } from '../build/dev/javascript/eyg_parser/eyg/parser.mjs';
import * as state from '../build/dev/javascript/eyg_interpreter/eyg/interpreter/state.mjs';
import { default$ as builtins } from '../build/dev/javascript/eyg_interpreter/eyg/interpreter/builtin.mjs';
import * as value from '../build/dev/javascript/eyg_interpreter/eyg/interpreter/value.mjs';
import { UnhandledEffect } from '../build/dev/javascript/eyg_interpreter/eyg/interpreter/break.mjs';
import { describe } from '../build/dev/javascript/eyg_interpreter/eyg/interpreter/simple_debug.mjs';
import { toList as fromArray } from '../build/dev/javascript/eyg_interpreter/gleam.mjs';
import { from_list, to_list } from '../build/dev/javascript/gleam_stdlib/gleam/dict.mjs';

// Only plain data crosses the worker boundary, never DOM nodes or JS functions.
function encode(data, depth = 0) {
  if (depth > 32) throw new Error('Effect data is nested too deeply.');
  if (typeof data === 'string') return new value.String(data);
  if (Number.isSafeInteger(data)) return new value.Integer(data);
  if (typeof data === 'boolean') return value.bool(data);
  if (Array.isArray(data))
    return new value.LinkedList(fromArray(data.map((x) => encode(x, depth + 1))));
  if (data && typeof data === 'object')
    return new value.Record(
      from_list(fromArray(Object.entries(data).map(([k, v]) => [k, encode(v, depth + 1)]))),
    );
  if (data === null || data === undefined) return value.unit();
  throw new Error('The handler returned unsupported data.');
}
function decode(data, depth = 0) {
  if (depth > 32) throw new Error('Result is nested too deeply.');
  if (data instanceof value.String || data instanceof value.Integer) return data.value;
  if (data instanceof value.LinkedList)
    return Array.from(data.elements).map((x) => decode(x, depth + 1));
  if (data instanceof value.Record)
    return Object.fromEntries(
      Array.from(to_list(data.fields)).map(([k, v]) => [k, decode(v, depth + 1)]),
    );
  if (data instanceof value.Tagged)
    return { tag: data.label, value: decode(data.value, depth + 1) };
  throw new Error('Only strings, integers, records, lists and tags can leave EYG.');
}
let steps = 0,
  effects = 0,
  suspended;
function loop(next) {
  while (next instanceof state.Loop) {
    if (++steps > 250_000) throw new Error('EYG instruction limit exceeded.');
    next = state.step(next[0], next[1], next[2]);
  }
  const result = next[0];
  if (result.isOk()) return postMessage({ type: 'done', value: decode(result[0]), steps });
  const [reason, , env, k] = result[0];
  if (!(reason instanceof UnhandledEffect)) throw new Error(describe(reason));
  if (++effects > 64) throw new Error('EYG effect limit exceeded (64).');
  suspended = { env, k };
  postMessage({ type: 'effect', id: effects, name: reason[0], argument: decode(reason[1]) });
}
self.onmessage = ({ data }) => {
  try {
    if (data.type === 'start') {
      const parsed = all_from_string(data.code);
      if (!parsed.isOk()) throw new Error(format_error(parsed[0], data.code));
      loop(
        new state.Loop(
          new state.E(parsed[0]),
          builtins(fromArray([['context', encode(data.context)]])),
          new state.Empty(),
        ),
      );
    } else if (data.type === 'resume' && suspended) {
      const { env, k } = suspended;
      suspended = undefined;
      loop(new state.Loop(new state.V(encode(data.value)), env, k));
    }
  } catch (error) {
    postMessage({ type: 'error', message: error.message });
  }
};
