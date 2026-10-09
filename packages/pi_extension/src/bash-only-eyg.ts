// Level 1: the bash tool can only run the `eyg` command.
// Pi has no permission rules, so this is a tool_call handler.
// The eyg CLI performs every effect a program asks for, there is no policy at this level.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return undefined
    const command = String(event.input.command ?? "").trim()
    // Shell syntax could start other programs, so only a single eyg command is allowed.
    if (/^eyg(\s|$)/.test(command) && !/[;&|`$<>\n]/.test(command.replace(/'[^']*'/g, "''"))) return undefined
    return { block: true, reason: "Only the eyg command can be run, write a program with `eyg run -c '<code>'`." }
  })
}
