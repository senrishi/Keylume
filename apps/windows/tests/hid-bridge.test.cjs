const test=require('node:test');
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const {HIDBridge,validateReport}=require('../hid-bridge.cjs');
function report(values){const p=Array(64).fill(0);p.splice(0,values.length,...values);return p;}
function fixture(devices=[{path:'keyboard',usagePage:0xFF00,usage:2}]){const device=new EventEmitter();device.writes=[];device.write=async p=>device.writes.push(p);device.close=async()=>device.closed=true;const events=[];const bridge=new HIDBridge({devicesAsync:async()=>devices,HIDAsync:{open:async()=>device}},(...args)=>events.push(args));return {bridge,device,events};}
test('opens only one vendor RGB interface and adds report ID zero',async()=>{const{bridge,device}=fixture();await bridge.connect();const p=report([6,5]);await bridge.write(p);assert.deepEqual(device.writes[0],[0,...p]);await bridge.disconnect();assert.equal(device.closed,true);});
test('normalizes reports and publishes disconnect events',async()=>{const{bridge,device,events}=fixture();await bridge.connect();device.emit('data',Buffer.from([0,...report([0xAA,11,1])]));assert.equal(events[0][0],'report');assert.equal(events[0][1].length,64);device.emit('error',new Error('unplugged'));assert.equal(events[1][0],'disconnect');assert.equal(bridge.device,null);});
test('rejects standard keyboard and ambiguous devices',async()=>{await assert.rejects(fixture([{usagePage:1,usage:6}]).bridge.connect(),/not found/);await assert.rejects(fixture([{usagePage:0xFF00,usage:2},{usagePage:0xFF00,usage:2}]).bridge.connect(),/only one/);});
test('rejects firmware commands, bad report lengths, and invalid lighting types',()=>{assert.throws(()=>validateReport(report([6,85])),/allowlist/);assert.throws(()=>validateReport([6,5]),/Invalid/);assert.throws(()=>validateReport(report([6,11,11,0,0,0,0,6,4,2])),/configuration/);assert.doesNotThrow(()=>validateReport(report([6,11,11,0,0,1,0,6,4,2])));});
