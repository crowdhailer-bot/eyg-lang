const open = document.querySelector('#show-injection');
const box = document.querySelector('.injection');
const code =
  "const script = document.createElement('script');\nscript.src = '" +
  location.origin +
  "/dist/phantom.js';\ndocument.head.append(script);";
box.querySelector('pre').textContent = code;
open.addEventListener('click', () => {
  box.hidden = !box.hidden;
  open.setAttribute('aria-expanded', String(!box.hidden));
});
box.querySelector('button').addEventListener('click', async () => {
  const button = box.querySelector('button');
  button.disabled = true;
  button.textContent = 'Injecting…';
  const script = document.createElement('script');
  script.src = '/dist/phantom.js';
  script.onload = () => {
    box.hidden = true;
    button.disabled = false;
    button.textContent = 'Run injection ↗';
    open.textContent = 'Injection code';
    window.Phantom.dock('right');
  };
  script.onerror = () => {
    button.disabled = false;
    button.textContent = 'Build missing — run npm run build';
  };
  document.head.append(script);
});
