export type EffectRecord = { label: string; input: string; output: string; decision?: string };
export type StructuralChunk = { text: string; token?: string; selected?: boolean; error?: boolean; path?: number[] };
export type StructuralView = { lines: StructuralChunk[][]; source: string; type: string; errors: string[]; message?: string; input?: { label: string; value: string; hints: [string, string][]; kind: "text" | "file" | "package" } };
export type StructuralAction =
  | { action: "enter"; source?: string }
  | { action: "key"; key: string }
  | { action: "answer"; text: string }
  | { action: "paste"; text: string }
  | { action: "focus"; path: number[] }
  | { action: "cancel" };
export type RuntimeEvent =
  | { type: "structure"; view: StructuralView }
  | { type: "clipboard"; text: string }
  | { type: "ready"; packages: string[] }
  | { type: "overlay-ready"; model: string }
  | { type: "assistant"; id: number; text: string }
  | { type: "tool"; id: number; name: string; code: string }
  | { type: "tool-result"; id: number; text: string; error: boolean; duration: number }
  | { type: "packages"; packages: string[] }
  | { type: "output"; id: number; text: string; error?: boolean }
  | { type: "effect"; id: number; effect: EffectRecord }
  | { type: "fetch"; id: number; url: string }
  | { type: "prompt"; id: number; text: string }
  | { type: "complete"; id: number; results: { text: string; error: boolean }[]; pending: string; duration: number }
  | { type: "error"; id: number; message: string };

export type RuntimeRequest =
  | { type: "initialize"; args: string[] }
  | { type: "evaluate"; id: number; source: string; structural?: boolean }
  | ({ type: "structure" } & StructuralAction)
  | { type: "answer"; text: string };
