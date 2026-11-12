import {keys} from './layout.js';
export function validatePreset(value,fallback='Imported layout'){
 if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Expected a preset object.');
 const raw=value.colors??value;
 if(!raw||typeof raw!=='object'||keys.some(k=>typeof raw[k]!=='string'||! /^[0-9a-f]{6}$/i.test(raw[k])))throw new Error('Preset must contain all 61 keys with six-digit RGB colors.');
 const effect=value.colors?(value.effect??-1):-1;
 const level=value.colors?(value.brightness??100):100,speed=value.colors?(value.speed??1):1;
 if(![-1,...Array.from({length:14},(_,i)=>i+2)].includes(effect)||!Number.isInteger(level)||level<0||level>100||!Number.isInteger(speed)||speed<0||speed>3)throw new Error('Invalid lighting settings in preset.');
 return {name:typeof value.name==='string'?value.name.slice(0,60):fallback,colors:Object.fromEntries(keys.map(k=>[k,raw[k].toUpperCase()])),effect,brightness:level,speed};
}
