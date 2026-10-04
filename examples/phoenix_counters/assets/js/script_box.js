// A textarea over a copy of its text highlighted with the EYG TextMate grammar.
// Enter submits the form, shift+enter adds a new line.
import {createHighlighterCore} from "shiki/core"
import {createJavaScriptRegexEngine} from "shiki/engine/javascript"
import githubDark from "shiki/themes/github-dark.mjs"
import grammar from "../../../../packages/vscode-eyg/syntaxes/eyg.tmLanguage.json"

const highlighter = createHighlighterCore({
  langs: [grammar],
  themes: [githubDark],
  engine: createJavaScriptRegexEngine(),
})

export const ScriptBox = {
  mounted() {
    this.input = this.el.querySelector("textarea")
    this.output = this.el.querySelector("pre")
    this.input.addEventListener("input", () => this.highlight())
    this.input.addEventListener("scroll", () => {
      this.output.scrollTop = this.input.scrollTop
      this.output.scrollLeft = this.input.scrollLeft
    })
    this.input.addEventListener("keydown", event => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()
        this.input.form.requestSubmit()
      }
    })
    this.handleEvent("clear", () => {
      this.input.value = ""
      this.input.dispatchEvent(new Event("input", {bubbles: true}))
    })
    this.highlight()
  },
  async highlight() {
    const source = this.input.value
    const {tokens, fg} = (await highlighter).codeToTokens(source, {lang: "eyg", theme: "github-dark"})
    this.output.replaceChildren(...tokens.flatMap((line, index) => {
      const spans = line.map(token => {
        const span = document.createElement("span")
        span.style.color = token.color ?? fg
        span.textContent = token.content
        return span
      })
      return index === 0 ? spans : [document.createTextNode("\n"), ...spans]
    }))
    // A trailing new line needs content after it to take up space
    this.output.append(document.createTextNode("\n "))
  },
}
