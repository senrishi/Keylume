import test from 'node:test';
import assert from 'node:assert/strict';
import {KeyboardDriver} from '../driver.js';
import {blank,keys,keyMap,scaled} from '../layout.js';
import {validatePreset} from '../preset.js';
import {readFileSync} from 'node:fs';
function mock(){const driver=new KeyboardDriver(null),packets=[];let active=22;
 driver.device={opened:true,sendReport:async(id,p)=>{packets.push([...p]);const r=new Uint8Array(64);r.set([0xAA,p[1]]);if(p[1]===22){r[2]=11;r[5]=1;r[7]=p[7];}if(p[1]===11){r[2]=1;r.set(p.slice(5,16),5);active=p[7];}if(p[1]===10){r[2]=11;r[5]=1;r[7]=active;r[8]=4;r[9]=2;}if(p[1]===20){r[2]=1;r[3]=p[3];r[4]=p[4];r.set(p.slice(8,11),8);}queueMicrotask(()=>driver.report({data:new DataView(r.buffer)}));},removeEventListener(){}};
 return {driver,packets};}
test('FE12 effect preserves config type 1 and checks device readback',async()=>{const {driver,packets}=mock();await driver.effect(6,4,2);assert.deepEqual(packets.map(p=>p[1]),[22,11,10]);assert.equal(packets[1][5],1);assert.equal(packets[1][7],6);assert.equal(packets[1][9],2);});
test('all 61 static colors use verified physical offsets and scaled brightness',async()=>{const{driver,packets}=mock(),colors=blank();colors.Esc='FF8040';await driver.layout(colors,50);const writes=packets.filter(p=>p[1]===20);assert.equal(writes.length,61);assert.deepEqual(writes[0].slice(8,11),[128,64,32]);for(let i=0;i<keys.length;i++)assert.equal(writes[i][3]+writes[i][4]*256,keyMap[keys[i]]*3);});
test('readback mismatch rejects effect rather than claiming success',async()=>{const{driver}=mock();await assert.rejects(driver.effect(6,3,2),/readback/);});
test('invalid arguments and unsupported commands never reach device',async()=>{const{driver,packets}=mock();await assert.rejects(driver.effect(85,4,2),/Invalid/);await assert.rejects(driver.exchange([6,85]),/blocked/);await assert.rejects(driver.layout({},100),/Invalid/);assert.equal(packets.length,0);});
test('catalog and RS validate; bottom row stays off in monogram',()=>{const catalog=JSON.parse(readFileSync(new URL('../presets.json',import.meta.url)));assert.equal(catalog.length,140);for(const p of catalog)assert.equal(Object.keys(validatePreset(p.colors).colors).length,61);const rs=validatePreset(JSON.parse(readFileSync(new URL('../rs.json',import.meta.url))));for(const k of ['Ctrl','Win','Alt','Space','RAlt','App','RCtrl','Fn'])assert.equal(rs.colors[k],'000000');});
test('preset imports reject malformed settings and preserve firmware choices',()=>{assert.throws(()=>validatePreset({colors:blank(),brightness:101}),/Invalid/);assert.throws(()=>validatePreset({Esc:'bad'}),/61 keys/);assert.equal(validatePreset({name:'Bloom',colors:blank(),effect:6,speed:2,brightness:70}).effect,6);assert.equal(scaled('FF8040',50),'804020');});
test('reports match command, respect DataView offsets, and ignore stale replies',async()=>{const driver=new KeyboardDriver(null);let done=false;driver.pending={command:11,timer:null,resolve:r=>{done=r[2]===1;}};driver.report({data:new DataView(Uint8Array.from([0xAA,10,...Array(62).fill(0)]).buffer)});assert.equal(done,false);const buffer=new Uint8Array(70);buffer.set([0xAA,11,1],3);driver.report({data:new DataView(buffer.buffer,3,64)});assert.equal(done,true);});
test('desktop transport carries reports through the shared protocol driver',async()=>{
 const {desktopHID}=await import('../desktop-hid.js');let onReport,onDisconnect,written;
 const adapter=desktopHID({connect:async()=>{},disconnect:async()=>{},send:async packet=>{written=packet;const reply=Array(64).fill(0);reply[0]=0xAA;reply[1]=packet[1];queueMicrotask(()=>onReport(reply));},onReport:fn=>onReport=fn,onDisconnect:fn=>onDisconnect=fn});
 const driver=new KeyboardDriver(adapter);await driver.connect();await driver.exchange([6,5]);assert.equal(written.length,64);assert.equal(written[1],5);onDisconnect();assert.equal(driver.device,null);
});
