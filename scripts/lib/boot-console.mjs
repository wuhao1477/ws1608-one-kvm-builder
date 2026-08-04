const CONSOLE_MODES = new Set(['both', 'display', 'serial']);

function readConsoleValue(envText) {
  for (const rawLine of String(envText ?? '').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    if (line.slice(0, separator) === 'console') return line.slice(separator + 1);
  }
  throw new Error('armbianEnv.txt has no console setting');
}

function assertBootBranches(bootCmdText) {
  const bootCmd = String(bootCmdText ?? '');
  if (!bootCmd.includes('console=tty1')) {
    throw new Error('boot script does not add console=tty1');
  }
  if (!bootCmd.includes('console=ttyAML0,115200n8')) {
    throw new Error('boot script does not add console=ttyAML0,115200n8');
  }
}

export function validateBootConsole(envText, bootCmdText) {
  const value = readConsoleValue(envText);
  if (/^["']|["']$/.test(value)) {
    throw new Error('console must be unquoted for U-Boot env import');
  }
  if (!CONSOLE_MODES.has(value)) {
    throw new Error(`unsupported console mode: ${value}`);
  }
  assertBootBranches(bootCmdText);

  const args = [];
  if (value === 'both' || value === 'display') args.push('console=tty1');
  if (value === 'both' || value === 'serial') args.push('console=ttyAML0,115200n8');
  args.push('no_console_suspend', 'consoleblank=0');
  return args;
}
