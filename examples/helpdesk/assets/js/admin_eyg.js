// Highlights EYG in AshAdmin with the TextMate grammar from the VS Code extension.
// AshAdmin owns its page, so instead of changing its markup the highlighted source
// is drawn over the `source` textarea, whose own text is transparent, and the
// result of a run is highlighted in place each time AshAdmin renders it.
import {createHighlighterCore} from "shiki/core"
import {createJavaScriptRegexEngine} from "shiki/engine/javascript"
import githubDark from "shiki/themes/github-dark.mjs"
import grammar from "../../../../packages/vscode-eyg/syntaxes/eyg.tmLanguage.json"

const SOURCE = 'textarea[name$="[source]"]'
const RESULT = ".max-w-2xl.mx-auto.mt-6 > div"
const ERROR = `${SOURCE} ~ p.text-rose-600`

const style = document.createElement("style")
style.textContent = `
  ${SOURCE}, ${RESULT}, .eyg-overlay {
    font-family: ui-monospace, monospace !important;
    font-size: 0.9rem !important;
    line-height: 1.5 !important;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  ${SOURCE} {
    min-height: 14rem;
    color: transparent !important;
    caret-color: #e1e4e8;
    background: #24292e !important;
  }
  ${RESULT} { background: #24292e !important; color: #e1e4e8; }
  .eyg-overlay {
    position: fixed;
    margin: 0;
    overflow: hidden;
    pointer-events: none;
    box-sizing: border-box;
    border-style: solid;
    border-color: transparent;
    z-index: 10;
  }
  /* Type errors are shown under the source, hide AshAdmin's summary of them */
  form:has(${SOURCE}) > div.mb-4.text-rose-600 { display: none; }
  ${ERROR} { display: block; white-space: pre-wrap; font-family: ui-monospace, monospace; }
`
document.head.append(style)

const highlighter = await createHighlighterCore({
  langs: [grammar],
  themes: [githubDark],
  engine: createJavaScriptRegexEngine(),
})

function highlight(source) {
  const {tokens, fg} = highlighter.codeToTokens(source, {lang: "eyg", theme: "github-dark"})
  return tokens.flatMap((line, index) => {
    const spans = line.map(token => {
      const span = document.createElement("span")
      span.className = "eyg-token"
      span.style.color = token.color ?? fg
      span.textContent = token.content
      return span
    })
    return index === 0 ? spans : [document.createTextNode("\n"), ...spans]
  })
}

let overlay = null

function frame() {
  const input = document.querySelector(SOURCE)
  if (!input) {
    overlay?.remove()
    overlay = null
    return
  }
  input.spellcheck = false
  if (!overlay) {
    overlay = document.createElement("pre")
    overlay.className = "eyg-overlay"
    document.body.append(overlay)
  }

  const rect = input.getBoundingClientRect()
  const computed = getComputedStyle(input)
  Object.assign(overlay.style, {
    top: `${rect.top}px`,
    left: `${rect.left}px`,
    width: `${rect.width}px`,
    height: `${rect.height}px`,
    padding: computed.padding,
    borderWidth: computed.borderWidth,
  })
  if (overlay.dataset.source !== input.value) {
    overlay.dataset.source = input.value
    // A trailing new line needs content after it to take up space
    overlay.replaceChildren(...highlight(input.value), document.createTextNode("\n "))
  }
  overlay.scrollTop = input.scrollTop

  // Rendered errors are surrounded by the whitespace of AshAdmin's template
  for (const error of document.querySelectorAll(ERROR)) {
    if (error.textContent !== error.textContent.trim()) error.textContent = error.textContent.trim()
  }

  const result = document.querySelector(RESULT)
  if (result && !result.querySelector(".eyg-token")) {
    result.replaceChildren(...highlight(result.textContent.trim()))
  }
}

requestAnimationFrame(function loop() {
  frame()
  requestAnimationFrame(loop)
})
