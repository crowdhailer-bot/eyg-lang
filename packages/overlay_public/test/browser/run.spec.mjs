import { test, expect } from '@playwright/test';
import { agent } from './agent.mjs';

test('the agent receives printed output and the result of a program', async ({ page }) => {
  const overlay = await agent(page);
  const result = await overlay.run('let _ = perform Print("hello ") !int_add(1, 2)');
  expect(result.content).toBe('Output:\nhello \nResult:\n3');
  await expect(page.locator('.message.assistant', { hasText: 'Done.' })).toHaveCount(1);
});
