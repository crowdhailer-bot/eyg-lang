// Types for runtime.js, the EYG runtime built from the opencode_plugin package in github.com/CrowdHailer/eyg-lang.
// Values from the runtime are opaque, Gleam results have `isOk()` and hold their value at index 0.
type Result<T, E> = { isOk(): boolean; 0: T | E }
type List<T> = { toArray(): T[] }
type Opaque = { readonly __eyg: unique symbol }

export type Policy = Opaque
export type Config = Opaque
export type Value = Opaque
export type Host = Opaque
export type Report = Opaque & { ok: boolean }

export function toList<T>(items: T[]): List<T>
export function load(path: string): Promise<Result<Config, string>>
export function load_source(code: string, path: string): Promise<Result<Config, string>>
export function config_policy(config: Config): Policy
export function config_context(config: Config): Value
export function config_readme(config: Config): string
export function agent_policy(config: Config, name: string): Result<Policy, undefined>
export function agent_names(config: Config): List<string>
export function restrict(parent: Policy, child: Value): Result<Policy, string>
export function replace(child: Value): Result<Policy, string>
export function field(value: Value, name: string): Result<Value, undefined>
export function fields(policy: Policy): List<string>
export function host(
  label: string,
  lift: string,
  lower: string,
  handler: (input: any, raw: Value) => Promise<unknown>,
): Host
export function describe(policy: Policy, hosts: List<Host>): string
export function run(code: string, policy: Policy, context: Value, directory: string, hosts: List<Host>): Promise<Report>
export function report_ok(report: Report): boolean
export function report_text(report: Report): string
export function report_effects(report: Report): List<string>
