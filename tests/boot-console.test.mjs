import assert from 'node:assert/strict';
import test from 'node:test';

import { validateBootConsole } from '../scripts/lib/boot-console.mjs';

const BOOT_CMD = `
test "${'${console}'}" = "display" || test "${'${console}'}" = "both" && setenv consoleargs "${'${consoleargs}'} console=tty1"
test "${'${console}'}" = "serial" || test "${'${console}'}" = "both" && setenv consoleargs "${'${consoleargs}'} console=ttyAML0,115200n8"
setenv consoleargs "${'${consoleargs}'} no_console_suspend consoleblank=0"
`;

test('rejects quoted console values preserved by U-Boot env import', () => {
  assert.throws(
    () => validateBootConsole('console="both"\n', BOOT_CMD),
    /console must be unquoted/,
  );
});

test('derives display and serial console arguments from unquoted both', () => {
  assert.deepEqual(
    validateBootConsole('console=both\n', BOOT_CMD),
    ['console=tty1', 'console=ttyAML0,115200n8', 'no_console_suspend', 'consoleblank=0'],
  );
});

test('rejects a boot script missing a display console branch', () => {
  assert.throws(
    () => validateBootConsole('console=display\n', BOOT_CMD.replace('console=tty1', '')),
    /boot script does not add console=tty1/,
  );
});
