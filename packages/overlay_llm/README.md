# Overlay LLM

A unified API for LLM chat completion across providers.

Included providers are:
- [Mistral](https://mistral.ai/)
- [Ollama](https://ollama.com/)
- OpenAI compatible chat completions, i.e. [OpenAI](https://openai.com/), [OpenRouter](https://openrouter.ai/) and local servers.
  Streamed responses are buffered until the stream ends as tool call arguments arrive in fragments.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Credit

Created for [EYG](https://eyg.run/), a new integration focused programming language.