const call = (code) => ({ type: 'tool_call', name: 'run_eyg', arguments: { code } });
const say = (content) => ({ type: 'message', content });
const quote = JSON.stringify;

/** A deterministic stand-in for an LLM. It only sees conversation/tool data. */
export async function mockComplete({ messages, signal }) {
  await new Promise((resolve, reject) => {
    const abort = () => {
      clearTimeout(timer);
      reject(new Error('Run cancelled.'));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', abort);
      resolve();
    }, 380);
    signal?.addEventListener('abort', abort, { once: true });
  });
  const userIndex = messages.findLastIndex((message) => message.role === 'user');
  const request = messages[userIndex].content.toLowerCase();
  const results = messages
    .slice(userIndex + 1)
    .filter((message) => message.role === 'tool')
    .map((message) => JSON.parse(message.content));
  const action = /button|toggle/.test(request)
    ? 'button'
    : /hover|glow/.test(request)
      ? 'hover'
      : /bigger|larger|enlarge/.test(request)
        ? 'enlarge'
        : /train|shortlist|compare|departure|cheapest/.test(request)
          ? 'shortlist'
          : null;
  if (!action)
    return say(
      'This demo has a few prepared skills. Try “Make the graph bigger”, “Add a hover effect”, “Add a focus button”, or “Shortlist the two cheapest direct trains”.',
    );
  if (results.some((result) => !result.ok))
    return say(
      `I couldn’t complete that change. ${results.find((result) => !result.ok).error} Any writes from the failed run were undone.`,
    );
  if (!results.length) {
    const selector =
      action === 'button'
        ? 'main, [role="main"]'
        : action === 'shortlist'
          ? '[data-departure], button:has(h3), [class*="journey-card"], [class*="departure-card"]'
          : '[data-chart], [class*="chart"], [class*="graph"], canvas, svg';
    return call(`perform GetElements(${quote(selector)})`);
  }
  const elements = results[0].value;
  if (!Array.isArray(elements) || !elements.length)
    return say(
      'I couldn’t find the relevant page elements. Open a page with a visible graph or train results and try again. The demo pages have a reproducible example.',
    );
  if (results.length === 1) {
    if (action === 'button')
      return call(
        `perform InsertButton(${quote(/train|shortlist/.test(request) ? 'Toggle my shortlist' : 'Toggle focus mode')})`,
      );
    if (action === 'shortlist') {
      const priced = elements
        .map((element) => ({
          ...element,
          price: Number(
            element.text
              .match(/(\d[\d \u00a0]*)\s*(?:kr|svenska kronor|:-)/i)?.[1]
              ?.replace(/\s/g, ''),
          ),
        }))
        .filter((element) => Number.isFinite(element.price));
      const trains = priced.filter((element) =>
        /(?:^|\s|m)(direct|direkt)(?:\s|$)|\b0\s+byten\b/i.test(element.text),
      );
      if (trains.length < 2)
        return say(
          'I need at least two direct departures with visible prices in kr to make this shortlist. No changes made.',
        );
      const cheapest = [...trains].sort((a, b) => a.price - b.price).slice(0, 2);
      const lines = priced.map(
        (element) =>
          `let _ = perform SetAttribute({id: ${quote(element.id)}, name: "data-eyg-shortlist", value: ${quote(String(cheapest.some((train) => train.id === element.id)))}})`,
      );
      lines.push(
        'let _ = perform WriteCSS("[data-eyg-shortlist=true] { border: 2px solid #26705b; background-color: #f0f8f2; box-shadow: 0 5px 20px #183e3512; } [data-eyg-shortlist=false] { opacity: 0.38; }")',
      );
      lines.push(`{selected: 2, lowest_price: ${cheapest[0].price}}`);
      return call(lines.join('\n'));
    }
    const graph =
      elements.find(
        (element) => element.tag !== 'svg' && element.tag !== 'path' && element.width > 200,
      ) ?? elements.find((element) => element.width > 200);
    if (!graph)
      return say(
        'I found small graphics, but no chart large enough to confidently change. No changes made.',
      );
    const css =
      action === 'enlarge'
        ? `${graph.selector} { width: 100%; max-width: 100%; min-height: 390px; } ${graph.selector} svg, ${graph.selector} canvas { width: 100%; height: 180px !important; transform: scaleY(1.5); transform-origin: top left; margin-bottom: 90px; }`
        : `${graph.selector} { transition: transform 240ms ease, box-shadow 240ms ease; border-radius: 16px; } ${graph.selector}:hover { transform: translateY(-4px); box-shadow: 0 16px 42px #246c4930; }`;
    return call(`let _ = perform WriteCSS(${quote(css)})\n{updated: ${quote(graph.selector)}}`);
  }
  if (action === 'enlarge')
    return say(
      'More room for the bigger picture. The chart is taller and uses the available width.',
    );
  if (action === 'hover')
    return say('A little lift, a soft green glow. Hover over the graph to see it.');
  if (action === 'shortlist')
    return say(
      `Your two cheapest direct trains are highlighted, from ${results[1].value.lowest_price} kr. The other departures are still there for comparison.`,
    );
  return say('Your button is on the page. Click it to switch your changes off and on.');
}
