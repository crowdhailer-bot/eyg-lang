const properties = new Set(
  'width height min-width max-width min-height max-height display grid-template-columns gap padding padding-top padding-bottom padding-left padding-right margin margin-top margin-bottom margin-left margin-right border border-color border-radius border-width border-style background-color color font-size font-weight line-height letter-spacing box-shadow opacity transform transform-origin transition outline outline-offset overflow align-items justify-content flex flex-wrap order'.split(
    ' ',
  ),
);
const blockedElements =
  'script, style, link, meta, template, noscript, input, textarea, select, option, [data-phantom-owned]';
function text(value, max, label) {
  if (typeof value !== 'string' || !value.trim() || value.length > max)
    throw new Error(`${label} must be nonempty text (at most ${max} characters).`);
  return value;
}
function selectorFor(node) {
  if (/^[a-z][a-z0-9_-]*$/i.test(node.id) && document.querySelectorAll(`#${node.id}`).length === 1)
    return `#${node.id}`;
  for (const name of node.classList) {
    if (/^[a-z][a-z0-9_-]*$/i.test(name) && document.querySelectorAll(`.${name}`).length === 1)
      return `.${name}`;
  }
  const path = [];
  while (node && node !== document.documentElement) {
    const siblings = Array.from(node.parentElement?.children ?? []).filter(
      (x) => x.tagName === node.tagName,
    );
    path.unshift(`${node.localName}:nth-of-type(${siblings.indexOf(node) + 1})`);
    node = node.parentElement;
  }
  return `html > ${path.join(' > ')}`;
}
export function validateCSS(source) {
  text(source, 12_000, 'CSS');
  // No escaped identifiers, comments, at-rules, resources or generated content.
  // Browser parsing plus a property allowlist is intentionally conservative.
  if (/[\\@<]|\/\*|url\s*\(|image\s*\(|image-set\s*\(|attr\s*\(|expression\s*\(/i.test(source))
    throw new Error(
      'CSS must only contain presentation rules; external resources and escapes are disabled.',
    );
  const sheet = new CSSStyleSheet();
  const expandedProperties = new Set(properties);
  const probe = document.createElement('div').style;
  for (const property of properties) {
    probe.cssText = '';
    probe.setProperty(property, 'initial');
    for (const longhand of probe) expandedProperties.add(longhand);
  }
  sheet.replaceSync(source);
  if (!sheet.cssRules.length || sheet.cssRules.length > 24)
    throw new Error('Use between 1 and 24 CSS rules.');
  for (const rule of sheet.cssRules) {
    if (!(rule instanceof CSSStyleRule) || !rule.style.length || rule.cssRules?.length)
      throw new Error('Only nonempty, unnested style rules are allowed.');
    document.querySelectorAll(rule.selectorText);
    for (const property of rule.style) {
      if (!expandedProperties.has(property))
        throw new Error(`CSS property ${property} is not allowed.`);
      if (/var\s*\(/i.test(rule.style.getPropertyValue(property)))
        throw new Error('CSS variables are disabled; use literal presentation values.');
    }
  }
  return Array.from(sheet.cssRules, (rule) => rule.cssText).join('\n');
}

/** Trusted host capabilities. Each run journals its writes for rollback/undo. */
export function createBrowserHarness({ root = document.body } = {}) {
  const nodes = new Map(),
    buttons = new Map(),
    ids = new WeakMap(),
    history = [];
  let nextId = 1,
    active = null,
    enabled = true,
    destroyed = false;
  function syncButtons() {
    let index = 0;
    for (const [host, button] of buttons) {
      host.style.bottom = 28 + index++ * 62 + 'px';
      button.setAttribute('aria-pressed', String(enabled));
    }
  }
  function change(apply, revert, kind = 'page') {
    if (!active) throw new Error('Start a transaction before running effects.');
    const operation = { apply, revert, kind };
    active.push(operation);
    apply();
  }
  function target(id) {
    const node = nodes.get(id);
    if (!node || !root.contains(node) || !node.isConnected)
      throw new Error('This element is no longer on the page. Inspect it again.');
    return node;
  }
  const effects = {
    GetElements(query) {
      text(query, 400, 'Selector');
      return Array.from(root.querySelectorAll(query))
        .filter(
          (node) =>
            !node.matches(blockedElements) &&
            !node.closest('[data-phantom-owned]') &&
            node.getClientRects().length,
        )
        .slice(0, 40)
        .map((node) => {
          let id = ids.get(node);
          if (!id) {
            id = `node-${nextId++}`;
            ids.set(node, id);
            nodes.set(id, node);
          }
          const rect = node.getBoundingClientRect();
          return {
            id,
            selector: selectorFor(node),
            tag: node.localName,
            text: (node.innerText ?? node.textContent ?? '').trim().slice(0, 600),
            label: (node.getAttribute('aria-label') ?? '').slice(0, 600),
            width: Math.round(rect.width),
            height: Math.round(rect.height),
          };
        });
    },
    WriteCSS(source) {
      const css = validateCSS(source);
      const style = document.createElement('style');
      style.dataset.phantomOwned = '';
      style.textContent = css;
      change(
        () => document.head.append(style),
        () => style.remove(),
      );
      return { rules: css.split('\n').length };
    },
    InsertButton(label) {
      text(label, 64, 'Button label');
      const host = document.createElement('div');
      host.dataset.phantomOwned = '';
      host.style.cssText =
        'position:fixed;bottom:28px;left:max(28px, calc(50vw - 100px));z-index:2147483645';
      const shadow = host.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent =
        'button{font:600 14px system-ui;cursor:pointer;background:#183e35;color:white;padding:15px 22px;border:1px solid #42675d;border-radius:999px;box-shadow:0 8px 28px #123b3430}button:hover{background:#24574b}button:focus-visible{outline:3px solid #61ac96;outline-offset:4px}button[aria-pressed=false]{background:#fff;color:#183e35}';
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.setAttribute('aria-pressed', 'true');
      button.title = 'Toggle the changes made by Phantom';
      button.addEventListener('click', () => {
        if (active) return;
        enabled = !enabled;
        const operations = history.flat().filter((op) => op.kind === 'page');
        if (enabled) operations.forEach((op) => op.apply());
        else [...operations].reverse().forEach((op) => op.revert());
        syncButtons();
      });
      shadow.append(style, button);
      change(
        () => {
          document.body.append(host);
          buttons.set(host, button);
          syncButtons();
        },
        () => {
          host.remove();
          buttons.delete(host);
          syncButtons();
        },
        'button',
      );
      return { label, action: 'Toggle all Phantom page changes' };
    },
    SetAttribute(request) {
      if (!request || typeof request !== 'object')
        throw new Error('SetAttribute expects {id, name, value}.');
      const node = target(request.id);
      if (typeof request.name !== 'string' || !/^data-eyg-[a-z-]{1,40}$/.test(request.name))
        throw new Error('Only data-eyg-* presentation attributes are allowed.');
      text(request.value, 100, 'Attribute value');
      const before = node.getAttribute(request.name);
      change(
        () => node.setAttribute(request.name, request.value),
        () =>
          before === null
            ? node.removeAttribute(request.name)
            : node.setAttribute(request.name, before),
      );
      return { id: request.id, name: request.name, value: request.value };
    },
  };
  function restoreEnabled() {
    if (!enabled) {
      history.flat().forEach((op) => op.apply());
      enabled = true;
      syncButtons();
    }
  }
  return {
    effects,
    begin() {
      if (destroyed || active) throw new Error('The harness is closed or already running.');
      restoreEnabled();
      active = [];
    },
    commit() {
      if (!active) return;
      if (active.length) history.push(active);
      active = null;
    },
    rollback() {
      if (!active) return;
      [...active].reverse().forEach((op) => op.revert());
      active = null;
    },
    undo() {
      if (active) throw new Error('Wait for the current run to finish.');
      restoreEnabled();
      const last = history.pop();
      last
        ?.slice()
        .reverse()
        .forEach((op) => op.revert());
      return Boolean(last);
    },
    destroy() {
      this.rollback();
      restoreEnabled();
      while (this.undo()) {}
      nodes.clear();
      destroyed = true;
    },
    get canUndo() {
      return history.length > 0;
    },
  };
}
