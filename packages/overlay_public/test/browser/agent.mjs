import { expect } from '@playwright/test';

// An EYG string literal, only quotes and backslashes need escaping.
export const string = text => `"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;

// An EYG bundle file record with text content.
export const file = (path, media_type, text) =>
  `{path: ${string(path)}, media_type: ${string(media_type)}, content: !string_to_binary(${string(text)})}`;

// A scripted agent, each prompt is answered by running the next program with the run tool.
// Once the tool result arrives the agent finishes its turn.
export async function agent(page, { query = '' } = {}) {
  await page.addInitScript(() => {
    if (window !== window.top) return;
    sessionStorage.setItem('overlay.llm.provider', 'ollama');
    sessionStorage.setItem('overlay.llm.model', 'qwen3.5:397b');
    sessionStorage.setItem('overlay.llm.api_key', 'browser-test-only');
  });
  const programs = [];
  const results = [];
  await page.route('**/api/chat', async route => {
    const { messages } = route.request().postDataJSON();
    const last = messages[messages.length - 1];
    let message;
    if (last.role === 'tool') {
      results.push(last);
      message = { role: 'assistant', content: 'Done.', tool_calls: [] };
    } else {
      const code = programs.shift();
      message = { role: 'assistant', content: '', tool_calls: [{ function: { name: 'run', arguments: { code } } }] };
    }
    await route.fulfill({ contentType: 'application/x-ndjson', body: JSON.stringify({ message, done: true }) + '\n' });
  });
  await page.goto(`/overlay/${query}`);
  await expect(page.locator('.provider-label')).toContainText('qwen3.5');

  return {
    // Run a program as the agent and return the tool result the agent received.
    async run(code) {
      programs.push(code);
      const count = results.length;
      await page.locator('textarea').fill('Run the program');
      await page.locator('textarea').press('Enter');
      await expect.poll(() => results.length).toBe(count + 1);
      await expect(page.locator('.layout')).toHaveAttribute('data-agent-status', 'waiting');
      return results[count];
    },
    // Save files as an artifact and show it across the whole workspace.
    async show(files, name = 'test') {
      const result = await this.run(`let bundle = [${files.join(', ')}]
match perform Artifact({name: ${string(name)}, bundle}) {
  Ok(_) -> { perform Show({item: Artifact(${string(name)}), origin: {x: 0, y: 0}, size: {x: 1000, y: 1000}}) }
  Error(reason) -> { Error(reason) }
}`);
      expect(result.content).toBe('Ok({})');
      return page.frameLocator(`iframe.artifact-preview[title=${JSON.stringify(name)}]`).frameLocator('iframe');
    },
  };
}
