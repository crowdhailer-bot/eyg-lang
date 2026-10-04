// A local stand in for the Ollama chat API that streams a scripted agent.
//
// Each reply is chosen by how many assistant messages the conversation has.
// Programs are real EYG files run by Overlay, and replies that describe results
// read them from the tool result Overlay sends back, so nothing is invented.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const program = name => readFileSync(resolve(import.meta.dirname, 'agent', name), 'utf8');
const field = (text, name) => text.match(new RegExp(`${name}: ([^,\\n}]+)`))?.[1]?.trim();
const unquote = text => text?.replace(/^"|"$/g, '');

export const prompts = [
  'Build a live departures board for the bus stops at Camden Town Station',
  'Add the weather for the next few hours and a map of the routes',
  'Only show the 24 and 88, and switch the board to light mode',
];

export const steps = [
  {
    thinking: 'Camden Town Station has four bus stops, S, X, Y and T. I will fetch arrivals for each from TfL, pass the JSON to a studio page and render rows with a live countdown, route filters and a theme toggle.',
    content: 'I\'ll fetch live arrivals for the four stops at Camden Town Station and build a board with the studio design system.',
    program: '01-departures.eyg',
  },
  {
    thinking: 'Saved and shown. The workflow says to check the artifact: count the departures, read the next one and take a screenshot.',
    content: result => `Saved version ${field(result, 'version') ?? 1}. Let me check the board in its preview.`,
    program: '02-check.eyg',
  },
  {
    thinking: 'The check passed and the screenshot matches the design system.',
    content: result => {
      const arriving = unquote(field(result, 'arriving'));
      const when = arriving === 'Due' ? 'is due now' : `arrives in ${arriving}`;
      return `The board lists *${field(result, 'departures')} departures* across ${field(result, 'routes')} routes, soonest first. The next, to ${unquote(field(result, 'next'))}, ${when}, and every countdown ticks from TfL's expected arrival times.`;
    },
  },
  {
    thinking: 'Open-Meteo has hourly forecasts without a key. TfL route sequences include line geometry, so the map can draw real routes without map tiles. Then tile all three with main_stack, keeping the board in the main column.',
    content: 'I\'ll get the forecast from Open-Meteo and the route shapes for the 24, 29, 88 and 214 from TfL, then tile the three artifacts.',
    program: '03-weather-and-map.eyg',
  },
  {
    thinking: 'Both saved and the layout is applied.',
    content: () => 'Added *weather* and *map*. The departures board keeps the main column, with the route map and the next twelve hours of weather beside it.',
  },
  {
    thinking: 'This is a change to how the board is viewed, not new data. Drive the running preview with playwright instead of saving a new version.',
    content: 'I\'ll change the running board directly, rather than saving a new version.',
    program: '04-routes-and-theme.eyg',
  },
  {
    thinking: 'Routes filtered and the theme switched, confirmed by the screenshot.',
    content: result => {
      const routes = [...new Set((result.match(/"(\d+)"/g) || []).map(route => route.replaceAll('"', '')))];
      return `Done. The board now shows only the ${routes.join(' and ')} in light mode. These are live changes to the running artifact, the saved version is unchanged.`;
    },
  },
];

function words(text) {
  return text.match(/\S+\s*/g) || [];
}

// Ollama streams one JSON object per line.
function stream(step, messages, { wordDelay }) {
  const last = messages[messages.length - 1];
  const result = last?.role === 'tool' ? last.content : '';
  const content = typeof step.content === 'function' ? step.content(result) : step.content;
  const encoder = new TextEncoder();
  return new ReadableStream({
    async start(controller) {
      const send = message => controller.enqueue(encoder.encode(JSON.stringify({ model: 'studio', created_at: new Date().toISOString(), message: { role: 'assistant', content: '', ...message }, done: false }) + '\n'));
      const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
      for (const word of words(step.thinking || '')) {
        send({ thinking: word });
        await pause(wordDelay / 2);
      }
      for (const word of words(content)) {
        send({ content: word });
        await pause(wordDelay);
      }
      if (step.program) {
        await pause(wordDelay * 4);
        send({ tool_calls: [{ function: { name: 'run', arguments: { code: program(step.program) } } }] });
      }
      controller.enqueue(encoder.encode(JSON.stringify({ model: 'studio', message: { role: 'assistant', content: '' }, done: true }) + '\n'));
      controller.close();
    },
  });
}

export function serve({ port = 11434, wordDelay = 45, onToolResult = () => {} } = {}) {
  return Bun.serve({
    port,
    hostname: '127.0.0.1',
    async fetch(request) {
      const url = new URL(request.url);
      if (request.method !== 'POST' || url.pathname !== '/api/chat') return new Response('Not found', { status: 404 });
      const { messages } = await request.json();
      const last = messages[messages.length - 1];
      if (last?.role === 'tool') onToolResult(last);
      const step = steps[messages.filter(message => message.role === 'assistant').length];
      if (!step) return new Response(JSON.stringify({ error: 'The scripted conversation has ended' }), { status: 500 });
      return new Response(stream(step, messages, { wordDelay }), { headers: { 'content-type': 'application/x-ndjson' } });
    },
  });
}
