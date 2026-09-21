export function now() {
  return performance.now();
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
