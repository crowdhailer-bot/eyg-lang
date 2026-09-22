export function now() {
  return performance.now();
}

// Keep the selection in view by scrolling the program panel vertically only.
export function scroll_to_selection() {
  const selection = document.querySelector(".code .selection");
  if (!selection) return;
  const panel = selection.closest(".panel");
  const top = selection.getBoundingClientRect().top - panel.getBoundingClientRect().top + panel.scrollTop;
  if (top < panel.scrollTop + 40 || top > panel.scrollTop + panel.clientHeight - 60) {
    panel.scrollTo({ top: Math.max(0, top - panel.clientHeight / 3), behavior: "smooth" });
  }
}
