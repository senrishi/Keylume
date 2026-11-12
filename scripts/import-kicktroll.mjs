import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, copyFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const upstream = resolve(process.argv[2] ?? new URL('../vendor/mk1300v2_RGB', import.meta.url).pathname);
const load = file => import(pathToFileURL(resolve(upstream, file)).href);
const { KEYBOARD_LAYOUT } = await load('keyboard-layout.js');
const { PATTERNS } = await load('effects.js');
const { EXTRA_PATTERNS } = await load('extra-effects.js');

const aliases = new Map([
  [33, '+'], [34, 'Back'], [97, 'RShift'], [115, 'RAlt'],
  [116, 'App'], [117, 'RCtrl'],
]);
const keyNames = KEYBOARD_LAYOUT.map(key => aliases.get(key.index) ?? key.name);
const localMap = readFileSync(new URL('../shared/key-map.h', import.meta.url), 'utf8');
const localKeys = Array.from(localMap.matchAll(/^\{("(?:\\.|[^"\\])*"), \d+\}/gm),
                            match => JSON.parse(match[1]));
assert.deepEqual([...keyNames].sort(), localKeys.sort());
assert.equal(new Set(keyNames).size, 61);

const categories = {
  contrasty: 'High Contrast', gradient: 'Gradient', neon: 'Neon / Cyber',
  heat: 'Fire / Heat', ice: 'Ice / Cryo', dark: 'Dark', pastel: 'Pastel',
  metallic: 'Metallic',
};
const app = readFileSync(resolve(upstream, 'app.js'), 'utf8');
const categoryBlock = app.match(/const PATTERN_CAT = \{([\s\S]*?)\n\};/);
assert.ok(categoryBlock, 'Kicktroll category map missing');
const categoryById = new Map(Array.from(categoryBlock[1].matchAll(/(\w+):'(\w+)'/g),
                                       ([, id, category]) => [id, category]));

const patterns = [...PATTERNS, ...EXTRA_PATTERNS];
assert.equal(new Set(patterns.map(pattern => pattern.id)).size, patterns.length);
const presets = patterns.map(({ id, name, fn }) => {
  const colors = fn(KEYBOARD_LAYOUT);
  assert.equal(colors.length, keyNames.length, name);
  return {
    id, name, category: categories[categoryById.get(id) ?? 'gradient'],
    colors: Object.fromEntries(colors.map(({ r, g, b }, index) => {
      assert.ok([r, g, b].every(value => Number.isInteger(value) && value >= 0 && value <= 255), name);
      return [keyNames[index], [r, g, b].map(value => value.toString(16).padStart(2, '0')).join('').toUpperCase()];
    })),
  };
});
writeFileSync(new URL('../shared/resources/Kicktroll-Presets.json', import.meta.url), JSON.stringify(presets) + '\n');
copyFileSync(resolve(upstream, 'LICENSE'), new URL('../shared/resources/Kicktroll-LICENSE.txt', import.meta.url));
console.log(`Imported ${presets.length} Kicktroll presets with ${keyNames.length} keys each.`);
