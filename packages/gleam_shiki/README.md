# Shiki bindings

Bindings to Shiki 4.5.0 using its JavaScript regex engine and GitHub Dark theme.
`create(grammar_json)` returns the native highlighter. `highlight` calls its
token API and decodes foreground colors and token lines in Gleam.

```sh
bun install
gleam build --warnings-as-errors
gleam test
```

The tests use the repository's EYG TextMate grammar and preserve complete Unicode
source and line breaks. Consumers render token content as
DOM text nodes; the highlighter does not insert HTML.
