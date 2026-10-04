export function isTty() {
  return Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;
}
