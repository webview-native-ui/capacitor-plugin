import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { NativeUIHandle, NativeUIOptions, NativeUIPlugin } from '../src/native/definitions';

let handle: NativeUIHandle | undefined;
beforeEach(() => vi.resetModules());
afterEach(async () => {
  await handle?.destroy();
  handle = undefined;
});

const fixture = async () => {
  const { installNativeUIHost } = await import('../src/host');
  const configure = vi.fn(async (_options?: Parameters<NativeUIPlugin['configure']>[0]) => ({ supported: false }));
  installNativeUIHost({
    plugin: { configure } as unknown as NativeUIPlugin,
    getPlatform: () => 'ios',
    isPluginAvailable: () => true,
  });
  const { enableNativeUI } = await import('../src/core');
  const start = async (options: NativeUIOptions = {}) => (handle = await enableNativeUI({ controls: false, ...options }));
  return { configure, start };
};

test.each([undefined, true, false])('startup forwards stopScrollOnActivate=%s with an enabled default', async (value) => {
  const { configure, start } = await fixture();
  await start(value === undefined ? {} : { stopScrollOnActivate: value });
  expect(configure).toHaveBeenCalledWith(expect.objectContaining({ stopScrollOnActivate: value !== false }));
});

test('omitted and true share a session; changing the setting requires restarting the handle', async () => {
  const { configure, start } = await fixture();
  const first = await start();
  expect(await start({ stopScrollOnActivate: true })).toBe(first);
  await expect(start({ stopScrollOnActivate: false })).rejects.toThrow('different controls');
  expect(configure).toHaveBeenCalledTimes(1);
  await first.destroy();
  await start({ stopScrollOnActivate: false });
  expect(configure).toHaveBeenLastCalledWith(expect.objectContaining({ stopScrollOnActivate: false }));
});
