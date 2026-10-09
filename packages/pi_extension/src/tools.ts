// Present tools as EYG effects.
// A tool `read` is the effect `Read`, `mcp__github__search` is `McpGithubSearch`.
// The policy field for an effect is its snake case, `ApplyPatch` is `apply_patch`, as in the runtime.

type Schema = {
  type?: string | string[]
  properties?: Record<string, Schema>
  required?: string[]
  items?: Schema | Schema[]
  anyOf?: Schema[]
}

export function label(name: string) {
  return name
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((part) => part[0]!.toUpperCase() + part.slice(1))
    .join("")
}

// EYG field names are lower case, so arguments such as `filePath` are written `file_path` in EYG.
export function snake(name: string) {
  return name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()
}

function first(schema: Schema | undefined) {
  return schema?.anyOf?.[0] ?? schema
}

/** An EYG type for a JSON schema, for describing the effect to the model. */
export function type(definition: Schema | undefined): string {
  const schema = first(definition)
  if (!schema) return "Any"
  const kind = Array.isArray(schema.type) ? schema.type[0] : schema.type
  if (kind === "string") return "String"
  if (kind === "integer" || kind === "number") return "Integer"
  if (kind === "boolean") return "True({}) | False({})"
  if (kind === "array") return `List(${type(Array.isArray(schema.items) ? schema.items[0] : schema.items)})`
  if (kind === "object" || schema.properties) {
    const required = new Set(schema.required ?? [])
    const fields = Object.entries(schema.properties ?? {}).map(
      ([name, field]) => `${snake(name)}${required.has(name) ? "" : "?"}: ${type(field)}`,
    )
    return `{${fields.join(", ")}}`
  }
  return "Any"
}

/** Arguments from EYG have snake case fields and no null, use the field names of the tool's schema. */
export function argument(value: unknown, definition: Schema | undefined): unknown {
  const schema = first(definition)
  if (Array.isArray(value)) {
    const items = schema?.items
    return value.map((item) => argument(item, Array.isArray(items) ? items[0] : items))
  }
  if (typeof value !== "object" || value === null || value instanceof Uint8Array) return value
  const properties = schema?.properties ?? {}
  return Object.fromEntries(
    Object.entries(value)
      .filter((entry) => entry[1] !== null && entry[1] !== undefined)
      .map(([key, item]) => {
        const name = Object.keys(properties).find((name) => snake(name) === key) ?? key
        return [name, argument(item, properties[name])]
      }),
  )
}

/** Results going back to EYG use snake case field names too. */
export function result(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(result)
  if (typeof value !== "object" || value === null || value instanceof Uint8Array) return value
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [snake(key), result(item)]))
}
