import css from './phantom.css';
import { createBrowserHarness } from './effects.mjs';
import { runAgent } from './agent.mjs';
import { mockComplete } from './mock.mjs';

const ghost =
  '<svg viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M7 26V14a9 9 0 0 1 18 0v12l-4-3-5 3-5-3-4 3Z" fill="#dce8cf" stroke="#527044" stroke-width="1.4"/><path d="M12 14v3m8-3v3" stroke="#527044" stroke-width="2" stroke-linecap="round"/></svg>';
const icons = {
  left: ['Dock left', '<rect x="2" y="2" width="12" height="12" rx="2"/><path d="M6 2v12"/>'],
  right: ['Dock right', '<rect x="2" y="2" width="12" height="12" rx="2"/><path d="M10 2v12"/>'],
  float: ['Float panel', '<rect x="4" y="4" width="10" height="10" rx="2"/><path d="M2 10V2h8"/>'],
  minimize: ['Minimize', '<path d="M3 8h10"/>'],
  close: ['Close and undo changes', '<path d="m4 4 8 8m0-8-8 8"/>'],
};
function mount() {
  if (window.Phantom) {
    window.Phantom.show();
    return;
  }
  const host = document.createElement('div');
  host.dataset.phantomOwned = '';
  host.id = 'eyg-phantom';
  const shadow = host.attachShadow({ mode: 'open' });
  const style = document.createElement('style');
  style.textContent = css;
  shadow.append(style);
  const panel = document.createElement('section');
  panel.className = 'panel';
  panel.setAttribute('aria-label', 'Phantom page assistant');
  panel.innerHTML =
    '<header class="header"><div class="brand-row"><div class="brand">' +
    ghost +
    'Phantom <span class="badge">DEMO</span></div><div class="tools">' +
    Object.entries(icons)
      .map(
        ([name, [label, paths]]) =>
          '<button class="icon" data-mode="' +
          name +
          '" title="' +
          label +
          '" aria-label="' +
          label +
          '"><svg viewBox="0 0 16 16" aria-hidden="true">' +
          paths +
          '</svg></button>',
      )
      .join('') +
    '</div></div><div class="status-row"><span class="dot"></span><span>Connected to this page</span><span class="site"></span></div></header><div class="feed" role="log" aria-label="Conversation" aria-live="polite"><div class="intro"><div class="eyebrow">A little more your internet</div><h1>Your page.<br>Your possibilities.</h1><p>Make the useful things stand out.<br>Tell me what you’d like to change.</p></div><div class="suggestions"></div></div><div class="bottom"><form class="composer"><textarea aria-label="Message Phantom" placeholder="What would make this page better?" rows="2" maxlength="4000"></textarea><div class="composer-footer"><span>EYG · ONE TOOL. EXPLICIT EFFECTS.</span><button class="send" aria-label="Send message" type="submit">↑</button></div></form><div class="footnote"><span>Mock agent · real EYG execution</span><button class="undo" type="button" disabled>Undo change ↶</button></div></div>';
  shadow.append(panel);
  document.body.append(host);
  const $ = (selector) => shadow.querySelector(selector);
  const feed = $('.feed'),
    input = $('textarea'),
    send = $('.send'),
    undo = $('.undo');
  const harness = createBrowserHarness();
  let mode = 'float',
    minimized = false,
    busy = false,
    controller,
    messages = [],
    closed = false;
  let position = { x: window.innerWidth - 420, y: 32 };
  const site = document.documentElement.dataset.demoSite || location.hostname;
  $('.site').textContent = site;
  const context = { site, title: document.title, mode: 'mock-demo' };
  const suggestions = /sj\.se/.test(site)
    ? ['Shortlist the two cheapest direct trains', 'Add a button to toggle my shortlist']
    : ['Make the graph bigger', 'Add a hover effect to the graph', 'Add a focus mode button'];
  for (const text of suggestions) {
    const button = document.createElement('button');
    button.className = 'suggestion';
    button.type = 'button';
    const label = document.createElement('b');
    label.style.fontWeight = '400';
    label.textContent = text;
    const arrow = document.createElement('span');
    arrow.textContent = '↗';
    button.append(label, arrow);
    button.addEventListener('click', () => {
      input.value = text;
      input.focus();
    });
    $('.suggestions').append(button);
  }
  const originalMargins = ['margin-left', 'margin-right'].map((name) => [
    name,
    document.body.style.getPropertyValue(name),
    document.body.style.getPropertyPriority(name),
  ]);
  const restoreMargins = () =>
    originalMargins.forEach(([name, value, priority]) =>
      value
        ? document.body.style.setProperty(name, value, priority)
        : document.body.style.removeProperty(name),
    );
  function layout() {
    restoreMargins();
    const mobile = innerWidth < 660;
    const width = Math.min(390, innerWidth - 24);
    host.style.cssText = 'position:fixed;z-index:2147483646;box-sizing:border-box;';
    if (minimized) {
      host.style.cssText += 'right:24px;bottom:24px;width:54px;height:54px';
      return;
    }
    if (mode !== 'float' || mobile) {
      const side = mode === 'left' ? 'left' : 'right';
      host.style.cssText += side + ':12px;top:12px;bottom:12px;width:' + width + 'px;';
      if (!mobile) document.body.style.setProperty('margin-' + side, width + 36 + 'px');
    } else {
      position.x = Math.max(12, Math.min(position.x, innerWidth - width - 12));
      position.y = Math.max(12, Math.min(position.y, innerHeight - 160));
      host.style.cssText +=
        'left:' +
        position.x +
        'px;top:' +
        position.y +
        'px;width:' +
        width +
        'px;height:' +
        Math.min(700, innerHeight - position.y - 12) +
        'px;';
    }
    shadow
      .querySelectorAll('[data-mode]')
      .forEach((button) =>
        button.setAttribute('aria-pressed', String(button.dataset.mode === mode)),
      );
  }
  const launcher = document.createElement('button');
  launcher.className = 'launcher';
  launcher.innerHTML = ghost;
  launcher.title = 'Open Phantom';
  launcher.setAttribute('aria-label', 'Open Phantom');
  const show = () => {
    minimized = false;
    launcher.remove();
    shadow.append(panel);
    layout();
    input.focus();
  };
  launcher.addEventListener('click', show);
  function close() {
    if (closed) return;
    closed = true;
    controller?.abort();
    harness.destroy();
    restoreMargins();
    window.removeEventListener('resize', layout);
    host.remove();
    delete window.Phantom;
  }
  for (const button of shadow.querySelectorAll('[data-mode]'))
    button.addEventListener('click', () => {
      const next = button.dataset.mode;
      if (next === 'close') return close();
      if (next === 'minimize') {
        minimized = true;
        panel.remove();
        shadow.append(launcher);
      } else mode = next;
      layout();
    });
  let drag;
  $('.header').addEventListener('pointerdown', (event) => {
    if (event.target.closest('button') || innerWidth < 660) return;
    const rect = host.getBoundingClientRect();
    mode = 'float';
    position = { x: rect.x, y: rect.y };
    drag = { x: event.clientX - rect.x, y: event.clientY - rect.y };
    event.currentTarget.setPointerCapture(event.pointerId);
    layout();
  });
  $('.header').addEventListener('pointermove', (event) => {
    if (drag) {
      position = { x: event.clientX - drag.x, y: event.clientY - drag.y };
      layout();
    }
  });
  $('.header').addEventListener('pointerup', () => {
    drag = null;
  });
  $('.header').addEventListener('pointercancel', () => {
    drag = null;
  });
  window.addEventListener('resize', layout);
  const scroll = () => {
    feed.scrollTop = feed.scrollHeight;
  };
  function message(role, content) {
    const node = document.createElement('div');
    node.className = 'message ' + role;
    node.textContent = content;
    feed.append(node);
    scroll();
    return node;
  }
  function onRun({ code }) {
    const card = document.createElement('div');
    card.className = 'run';
    card.innerHTML =
      '<div class="run-title"><span class="run-state running">◌</span><span class="run-name">Run EYG</span><span class="count">Running</span></div><details class="code"><summary>View code</summary><pre></pre></details><details class="effect-details" open><summary>Effects</summary><div class="effects"></div></details>';
    card.querySelector('pre').textContent = code;
    feed.append(card);
    scroll();
    const rows = new Map();
    let manuallyExpanded = false;
    card.querySelector('.effect-details summary').addEventListener('click', () => {
      manuallyExpanded = true;
    });
    return {
      onEffect(effect) {
        let row = rows.get(effect.id);
        if (!row) {
          row = document.createElement('div');
          row.innerHTML = '<span class="check"></span><span class="name"></span><small></small>';
          rows.set(effect.id, row);
          card.querySelector('.effects').append(row);
        }
        row.className = 'effect ' + effect.status;
        row.querySelector('.check').textContent =
          effect.status === 'done' ? '✓' : effect.status === 'error' ? '×' : '◌';
        row.querySelector('.name').textContent = effect.name;
        row.querySelector('small').textContent =
          effect.error ??
          (typeof effect.argument === 'string' ? effect.argument : JSON.stringify(effect.argument));
        card.querySelector('.effect-details summary').textContent =
          rows.size + ' effect' + (rows.size === 1 ? '' : 's');
        card.querySelector('.count').textContent =
          [...rows.values()].filter((row) => row.classList.contains('done')).length +
          '/' +
          rows.size +
          ' complete';
        if (rows.size > 4 && !manuallyExpanded) card.querySelector('.effect-details').open = false;
        scroll();
      },
      done(error) {
        card.dataset.status = error ? 'error' : 'done';
        const state = card.querySelector('.run-state');
        state.className = 'run-state ' + (error ? 'error' : '');
        state.textContent = error ? '×' : '✓';
        card.querySelector('.run-name').textContent = error ? 'Run stopped' : 'Ran EYG';
        if (error) {
          const detail = document.createElement('div');
          detail.className = 'run-error';
          detail.textContent = error.message;
          card.append(detail);
        }
        if (!rows.size) card.querySelector('.count').textContent = error ? 'Failed' : 'Complete';
        undo.disabled = busy || !harness.canUndo;
        scroll();
      },
    };
  }
  async function submit(event) {
    event?.preventDefault();
    if (busy) {
      controller.abort();
      return;
    }
    const prompt = input.value.trim();
    if (!prompt) return;
    busy = true;
    controller = new AbortController();
    send.textContent = '■';
    send.setAttribute('aria-label', 'Stop response');
    input.value = '';
    undo.disabled = true;
    message('user', prompt);
    messages.push({ role: 'user', content: prompt });
    const thinking = document.createElement('div');
    thinking.className = 'thinking';
    thinking.textContent = 'Reading the page…';
    feed.append(thinking);
    scroll();
    try {
      const response = await runAgent({
        messages,
        complete: mockComplete,
        harness,
        context,
        signal: controller.signal,
        onRun: (run) => {
          thinking.remove();
          return onRun(run);
        },
      });
      messages = response.messages;
      message('assistant', response.message);
    } catch (error) {
      message('assistant error', error.message);
    } finally {
      thinking.remove();
      busy = false;
      send.textContent = '↑';
      send.setAttribute('aria-label', 'Send message');
      undo.disabled = !harness.canUndo;
      input.focus();
    }
  }
  $('.composer').addEventListener('submit', submit);
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      submit();
    }
  });
  undo.addEventListener('click', () => {
    if (harness.undo()) {
      messages.push({
        role: 'user',
        content:
          'Host notice: I undid the most recent page change. Inspect again before your next change.',
      });
      message('assistant', 'The last page change has been undone.');
    }
    undo.disabled = !harness.canUndo;
  });
  window.Phantom = Object.freeze({
    show,
    close,
    dock(side) {
      if (!['left', 'right', 'float'].includes(side)) throw new Error('Use left, right or float.');
      mode = side;
      show();
    },
  });
  layout();
}
if (document.body) mount();
else document.addEventListener('DOMContentLoaded', mount, { once: true });
