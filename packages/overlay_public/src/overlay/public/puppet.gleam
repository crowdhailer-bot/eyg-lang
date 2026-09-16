//// The puppet script runs first in every artifact preview.
////
//// It performs requests from the application for the `Puppet` effect,
//// see `overlay/web/puppet` for the protocol and guides/overlay_artifacts.md for the pattern.
//// Only the application, the parent of the wrapper frame, can send requests
//// and each reply is posted to the MessagePort of its request.
//// An artifact can interfere with its own puppet, but not the application or
//// another artifact, so replies are only ever data about that artifact.

pub const script = "
(() => {
  // Only the application, two frames up past the wrapper, may send commands.
  const host = parent.parent;
  if (host === window) return;
  const requests = new Map();
  const normalize = text => String(text ?? '').replace(/\\s+/g, ' ').trim();
  const includes = (text, part) => normalize(text).toLowerCase().includes(normalize(part).toLowerCase());
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const frame = () => new Promise(resolve => requestAnimationFrame(() => resolve()));

  const roles = {
    button: 'button,input[type=button],input[type=submit],input[type=reset],summary',
    link: 'a[href]',
    heading: 'h1,h2,h3,h4,h5,h6',
    textbox: 'input:not([type]),input[type=text],input[type=email],input[type=search],input[type=url],input[type=tel],input[type=password],input[type=number],textarea',
    checkbox: 'input[type=checkbox]',
    radio: 'input[type=radio]',
    combobox: 'select',
    slider: 'input[type=range]',
    option: 'option',
    list: 'ul,ol',
    listitem: 'li',
    img: 'img[alt],svg[role=img]',
    table: 'table',
    row: 'tr',
    cell: 'td',
    columnheader: 'th',
    navigation: 'nav',
    main: 'main',
    article: 'article',
    region: 'section[aria-label],section[aria-labelledby]',
    dialog: 'dialog',
    form: 'form',
  };

  function labelText(element) {
    const labels = element.labels ? [...element.labels].map(label => label.textContent) : [];
    return labels.join(' ');
  }
  function accessibleName(element) {
    const labelledby = element.getAttribute('aria-labelledby');
    if (labelledby) return labelledby.split(/\\s+/).map(id => document.getElementById(id)?.textContent ?? '').join(' ');
    return element.getAttribute('aria-label') || labelText(element) || element.getAttribute('alt') || element.getAttribute('title') ||
      (element instanceof HTMLInputElement && ['button', 'submit', 'reset'].includes(element.type) ? element.value : '') ||
      element.textContent || element.getAttribute('placeholder') || '';
  }
  function visible(element) {
    if (!element.isConnected) return false;
    if (element.checkVisibility) return element.checkVisibility({ checkOpacity: false, checkVisibilityCSS: true }) && hasBox(element);
    const style = getComputedStyle(element);
    return style.visibility !== 'hidden' && style.display !== 'none' && hasBox(element);
  }
  function hasBox(element) {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }
  function descendants(roots) {
    return roots.flatMap(root => [...root.querySelectorAll('*')]);
  }
  // Elements matching text with no child that also matches, the most specific match.
  function byText(roots, text) {
    const matches = descendants(roots).filter(element => !['SCRIPT', 'STYLE', 'TEMPLATE'].includes(element.tagName) && includes(element.textContent, text));
    return matches.filter(element => !matches.some(other => other !== element && element.contains(other)));
  }
  function resolve(locator) {
    let elements = [document];
    for (const step of locator) {
      switch (step.type) {
        case 'css': elements = elements.flatMap(root => [...root.querySelectorAll(step.value)]); break;
        case 'text': elements = byText(elements, step.value); break;
        case 'role': {
          const implicit = roles[step.role] ? `,${roles[step.role]}` : '';
          elements = elements.flatMap(root => [...root.querySelectorAll(`[role=\"${CSS.escape(step.role)}\"]${implicit}`)])
            .filter(element => !step.name || includes(accessibleName(element), step.name));
          break;
        }
        case 'label': elements = descendants(elements).filter(element => element.labels !== undefined || element.hasAttribute('aria-label'))
          .filter(element => includes(element.getAttribute('aria-label') || labelText(element), step.value)); break;
        case 'placeholder': elements = elements.flatMap(root => [...root.querySelectorAll('[placeholder]')]).filter(element => includes(element.getAttribute('placeholder'), step.value)); break;
        case 'test_id': elements = elements.flatMap(root => [...root.querySelectorAll(`[data-testid=\"${CSS.escape(step.value)}\"]`)]); break;
        case 'has_text': elements = elements.filter(element => includes(element.textContent, step.value)); break;
        case 'nth': {
          const index = step.value < 0 ? elements.length + step.value : step.value;
          elements = index >= 0 && index < elements.length ? [elements[index]] : [];
          break;
        }
        default: throw new Error(`Unknown locator step ${step.type}`);
      }
      elements = [...new Set(elements)];
    }
    return elements.filter(element => element !== document);
  }
  function describe(locator) {
    return locator.map(step => {
      switch (step.type) {
        case 'role': return step.name ? `role=${step.role}[name=\"${step.name}\"]` : `role=${step.role}`;
        case 'nth': return `nth=${step.value}`;
        default: return `${step.type}=${JSON.stringify(step.value)}`;
      }
    }).join(' >> ') || 'page';
  }
  function summary(element) {
    const id = element.id ? `#${element.id}` : '';
    const text = normalize(element.textContent).slice(0, 40);
    return `<${element.localName}${id}>${text}`;
  }

  // Retry check until it returns, a fatal error or the timeout ends waiting.
  class Fatal extends Error {}
  async function poll(timeout, check) {
    const deadline = Date.now() + timeout;
    let failure = 'timed out';
    while (true) {
      try {
        return check();
      } catch (error) {
        if (error instanceof Fatal) throw error;
        failure = error.message;
      }
      if (Date.now() > deadline) throw new Error(`Timeout ${timeout}ms: ${failure}`);
      await sleep(50);
    }
  }
  // A single element that can be acted on, Playwright's strictness and actionability.
  function one(locator, timeout, { interactive = false } = {}) {
    return poll(timeout, () => {
      const elements = resolve(locator);
      if (elements.length === 0) throw new Error(`${describe(locator)} matched no elements`);
      if (elements.length > 1) throw new Fatal(`${describe(locator)} matched ${elements.length} elements: ${elements.slice(0, 3).map(summary).join(', ')}. Use first, nth or a more specific locator`);
      const [element] = elements;
      if (interactive && !visible(element)) throw new Error(`${describe(locator)} is not visible`);
      if (interactive && element.disabled) throw new Error(`${describe(locator)} is disabled`);
      return element;
    });
  }

  // Show where the agent acts and when it takes screenshots, removed before screenshots.
  let marker;
  let flash;
  async function point(element) {
    element.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    const rect = element.getBoundingClientRect();
    if (!marker) {
      marker = document.createElement('div');
      marker.setAttribute('aria-hidden', 'true');
      marker.style.cssText = 'all:initial;position:fixed;z-index:2147483647;pointer-events:none;border:2px solid #6d5dfc;border-radius:8px;box-shadow:0 0 0 4px rgba(109,93,252,.25);transition:all .25s ease;opacity:0';
    }
    if (!marker.isConnected) document.documentElement.append(marker);
    Object.assign(marker.style, { left: `${rect.left - 4}px`, top: `${rect.top - 4}px`, width: `${rect.width + 8}px`, height: `${rect.height + 8}px`, opacity: '1' });
    await sleep(260);
  }
  function unpoint() {
    if (marker) marker.style.opacity = '0';
  }

  function dispatchPointer(element, type) {
    const rect = element.getBoundingClientRect();
    const init = { bubbles: true, cancelable: true, composed: true, clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2, button: 0 };
    const Constructor = type.startsWith('pointer') ? PointerEvent : MouseEvent;
    element.dispatchEvent(new Constructor(type, init));
  }
  function setValue(element, value) {
    const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : element instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
    setter ? setter.call(element, value) : (element.value = value);
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
  }

  const done = { type: 'done' };
  const actions = {
    async click(locator, action, timeout) {
      const element = await one(locator, timeout, { interactive: true });
      await point(element);
      for (const type of ['pointerover', 'pointerenter', 'mouseover', 'pointerdown', 'mousedown']) dispatchPointer(element, type);
      if (element.focus) element.focus({ preventScroll: true });
      for (const type of ['pointerup', 'mouseup']) dispatchPointer(element, type);
      element.click();
      unpoint();
      return done;
    },
    async fill(locator, action, timeout) {
      const element = await one(locator, timeout, { interactive: true });
      await point(element);
      element.focus({ preventScroll: true });
      if (element.isContentEditable) {
        element.textContent = action.value;
        element.dispatchEvent(new Event('input', { bubbles: true }));
      } else if ('value' in element) {
        setValue(element, action.value);
      } else {
        throw new Error(`${describe(locator)} is not an input, textarea or contenteditable element`);
      }
      unpoint();
      return done;
    },
    async press(locator, action, timeout) {
      const element = locator.length ? await one(locator, timeout, { interactive: true }) : document.activeElement || document.body;
      if (locator.length) {
        await point(element);
        element.focus({ preventScroll: true });
      }
      const init = { key: action.value, bubbles: true, cancelable: true, composed: true };
      const proceed = element.dispatchEvent(new KeyboardEvent('keydown', init));
      if (proceed && action.value.length === 1 && 'value' in element && !(element instanceof HTMLSelectElement)) {
        setValue(element, element.value + action.value);
      }
      if (proceed && action.value === 'Enter' && element.form) element.form.requestSubmit();
      element.dispatchEvent(new KeyboardEvent('keyup', init));
      unpoint();
      return done;
    },
    async set_checked(locator, action, timeout) {
      const element = await one(locator, timeout, { interactive: true });
      if (element.checked !== action.value) {
        await point(element);
        element.click();
        unpoint();
      }
      if (element.checked !== action.value) throw new Error(`${describe(locator)} did not change checked state`);
      return done;
    },
    async select_option(locator, action, timeout) {
      const element = await one(locator, timeout, { interactive: true });
      if (!(element instanceof HTMLSelectElement)) throw new Error(`${describe(locator)} is not a select element`);
      const option = [...element.options].find(option => option.value === action.value || normalize(option.label) === normalize(action.value));
      if (!option) throw new Error(`${describe(locator)} has no option ${JSON.stringify(action.value)}`);
      await point(element);
      setValue(element, option.value);
      unpoint();
      return done;
    },
    async hover(locator, action, timeout) {
      const element = await one(locator, timeout, { interactive: true });
      await point(element);
      for (const type of ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointermove', 'mousemove']) dispatchPointer(element, type);
      return done;
    },
    async focus(locator, action, timeout) {
      const element = await one(locator, timeout);
      element.focus();
      return done;
    },
    async scroll_into_view(locator, action, timeout) {
      const element = await one(locator, timeout);
      element.scrollIntoView({ block: 'center' });
      return done;
    },
    async text_content(locator, action, timeout) {
      return { type: 'text', value: (await one(locator, timeout)).textContent ?? '' };
    },
    async inner_text(locator, action, timeout) {
      return { type: 'text', value: (await one(locator, timeout)).innerText ?? '' };
    },
    async inner_html(locator, action, timeout) {
      return { type: 'text', value: (await one(locator, timeout)).innerHTML };
    },
    async input_value(locator, action, timeout) {
      const element = await one(locator, timeout);
      if (!('value' in element)) throw new Error(`${describe(locator)} is not an input, textarea or select element`);
      return { type: 'text', value: String(element.value) };
    },
    async get_attribute(locator, action, timeout) {
      const value = (await one(locator, timeout)).getAttribute(action.value);
      return value === null ? { type: 'missing' } : { type: 'text', value };
    },
    async count(locator) {
      return { type: 'count', value: resolve(locator).length };
    },
    async all_text_contents(locator) {
      return { type: 'texts', value: resolve(locator).map(element => element.textContent ?? '') };
    },
    async is_visible(locator) {
      const [element] = resolve(locator);
      return { type: 'flag', value: Boolean(element && visible(element)) };
    },
    async is_checked(locator, action, timeout) {
      return { type: 'flag', value: Boolean((await one(locator, timeout)).checked) };
    },
    async is_enabled(locator, action, timeout) {
      return { type: 'flag', value: !(await one(locator, timeout)).disabled };
    },
    async expect(locator, action, timeout) {
      const { condition } = action;
      await poll(timeout, () => {
        const elements = resolve(locator);
        const single = () => {
          if (elements.length !== 1) throw new Error(`expected ${describe(locator)} to match one element, found ${elements.length}`);
          return elements[0];
        };
        switch (condition.type) {
          case 'to_have_count':
            if (elements.length === condition.value) return true;
            throw new Error(`expected ${describe(locator)} to have count ${condition.value}, found ${elements.length}`);
          case 'to_have_text': {
            const text = normalize(single().textContent);
            if (text === normalize(condition.value)) return true;
            throw new Error(`expected ${describe(locator)} to have text ${JSON.stringify(condition.value)}, found ${JSON.stringify(text)}`);
          }
          case 'to_contain_text': {
            const text = normalize(single().textContent);
            if (includes(text, condition.value)) return true;
            throw new Error(`expected ${describe(locator)} to contain text ${JSON.stringify(condition.value)}, found ${JSON.stringify(text.slice(0, 200))}`);
          }
          case 'to_be_visible':
            if (visible(single())) return true;
            throw new Error(`expected ${describe(locator)} to be visible`);
          case 'to_be_hidden':
            if (elements.every(element => !visible(element))) return true;
            throw new Error(`expected ${describe(locator)} to be hidden`);
          case 'to_have_value': {
            const value = String(single().value);
            if (value === condition.value) return true;
            throw new Error(`expected ${describe(locator)} to have value ${JSON.stringify(condition.value)}, found ${JSON.stringify(value)}`);
          }
          case 'to_have_attribute': {
            const value = single().getAttribute(condition.name);
            if (value === condition.value) return true;
            throw new Error(`expected ${describe(locator)} to have attribute ${condition.name}=${JSON.stringify(condition.value)}, found ${JSON.stringify(value)}`);
          }
          case 'to_be_checked':
            if (single().checked === condition.value) return true;
            throw new Error(`expected ${describe(locator)} to be ${condition.value ? 'checked' : 'unchecked'}`);
          default:
            throw new Error(`Unknown expectation ${condition.type}`);
        }
      });
      return done;
    },
    async screenshot(locator, action, timeout) {
      const element = locator.length ? await one(locator, timeout) : null;
      return { type: 'image', value: await screenshot(element) };
    },
  };

  // Render the document as an image: the DOM is serialized into SVG foreignObject.
  // Styles come from the document's own style elements, bundles have no external CSS.
  async function screenshot(element) {
    unpoint();
    if (marker) marker.remove();
    if (flash) flash.remove();
    if (document.readyState !== 'complete') await new Promise(resolve => addEventListener('load', resolve, { once: true }));
    if (document.fonts) await document.fonts.ready;
    await frame();
    const root = document.documentElement;
    const width = root.clientWidth;
    const height = Math.max(root.scrollHeight, innerHeight);
    const clone = root.cloneNode(true);
    const originals = root.querySelectorAll('*');
    const copies = clone.querySelectorAll('*');
    for (let index = 0; index < originals.length; index++) {
      const original = originals[index];
      const copy = copies[index];
      if (original instanceof HTMLCanvasElement) {
        try {
          const image = document.createElement('img');
          image.src = original.toDataURL();
          image.setAttribute('style', original.getAttribute('style') || '');
          image.width = original.width;
          image.height = original.height;
          image.className = original.className;
          copy.replaceWith(image);
        } catch {}
      } else if (original instanceof HTMLInputElement) {
        if (original.type === 'checkbox' || original.type === 'radio') {
          original.checked ? copy.setAttribute('checked', '') : copy.removeAttribute('checked');
        } else {
          copy.setAttribute('value', original.value);
        }
      } else if (original instanceof HTMLTextAreaElement) {
        copy.textContent = original.value;
      } else if (original instanceof HTMLOptionElement) {
        original.selected ? copy.setAttribute('selected', '') : copy.removeAttribute('selected');
      } else if (original instanceof HTMLScriptElement) {
        copy.remove();
      } else if (original instanceof HTMLStyleElement) {
        // The SVG document is the root, the HTML element takes the place of :root.
        copy.textContent = original.textContent.replaceAll(':root', 'html');
      }
    }
    const freeze = document.createElement('style');
    freeze.textContent = '*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;animation-iteration-count:1!important;animation-fill-mode:both!important;transition:none!important;caret-color:transparent!important}';
    clone.querySelector('head')?.append(freeze);
    clone.style.setProperty('width', `${width}px`);
    clone.style.setProperty('height', `${height}px`);
    const markup = new XMLSerializer().serializeToString(clone);
    const svg = `<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"${width}\" height=\"${height}\"><foreignObject x=\"0\" y=\"0\" width=\"${width}\" height=\"${height}\">${markup}</foreignObject></svg>`;
    const image = new Image();
    image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
    await image.decode();
    const rect = element ? element.getBoundingClientRect() : { left: 0, top: 0, width: innerWidth, height: innerHeight };
    const left = rect.left + scrollX;
    const top = rect.top + scrollY;
    const scale = Math.min(devicePixelRatio || 1, 2);
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(rect.width * scale));
    canvas.height = Math.max(1, Math.round(rect.height * scale));
    const context = canvas.getContext('2d');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, left, top, rect.width, rect.height, 0, 0, canvas.width, canvas.height);
    // The image is drawn, a brief flash now shows people a screenshot was taken.
    flash = document.createElement('div');
    flash.setAttribute('aria-hidden', 'true');
    flash.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none;background:#fff;opacity:0.65;transition:opacity 0.6s ease 0.25s';
    document.documentElement.append(flash);
    requestAnimationFrame(() => requestAnimationFrame(() => { flash.style.opacity = '0'; }));
    const shown = flash;
    setTimeout(() => shown.remove(), 1200);
    // Encoding off the main thread keeps the page responsive.
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
  }

  async function run(request) {
    const { locator = [], action = {}, timeout = 5000 } = request || {};
    const perform = actions[action.type];
    if (!perform) throw new Error(`Unknown action ${action.type}`);
    return perform(locator, action, timeout);
  }

  addEventListener('message', event => {
    if (event.source !== host) return;
    const { id, request } = event.data || {};
    const [port] = event.ports;
    if (typeof id !== 'string' || !port) return;
    const existing = requests.get(id);
    if (existing) {
      existing.reply ? port.postMessage(existing.reply) : existing.ports.push(port);
      return;
    }
    const entry = { ports: [port], reply: null };
    requests.set(id, entry);
    run(request)
      .catch(error => ({ type: 'error', value: String(error?.message ?? error) }))
      .then(reply => {
        entry.reply = reply;
        for (const waiting of entry.ports) waiting.postMessage(reply);
        entry.ports = [];
        setTimeout(() => requests.delete(id), 60_000);
      });
  });
})();
"
