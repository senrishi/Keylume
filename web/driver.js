import {keyMap,keys,scaled} from './layout.js';
export class KeyboardDriver {
  constructor(hid = globalThis.navigator?.hid) { this.hid=hid; this.device=null; this.pending=null; this.busy=false; this.onDisconnect=()=>{}; this.report=this.report.bind(this); hid?.addEventListener('disconnect',e=>{if(e.device===this.device){this.detach();this.onDisconnect();}}); }
  report(e) {
    const p=this.pending;
    const data=new Uint8Array(e.data.buffer,e.data.byteOffset,e.data.byteLength);
    if(p && data.length===64 && data[0]===0xAA && data[1]===p.command){this.pending=null;clearTimeout(p.timer);p.resolve(data.slice());}
  }
  detach() { this.device?.removeEventListener('inputreport',this.report);this.device=null; if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(new Error('Keyboard disconnected.'));this.pending=null;} }
  async connect() {
    if(!this.hid) throw new Error('WebHID is unavailable. Open this page over HTTPS in desktop Chrome or Edge.');
    const devices=await this.hid.requestDevice({filters:[{vendorId:0x36AE,productId:0xFE12,usagePage:0xFF00,usage:2}]});
    if(!devices.length) return false;
    const device=devices[0];
    if(!device.collections.some(c=>c.usagePage===0xFF00 && c.usage===2 && c.outputReports?.some(r=>r.items?.length))) throw new Error('The vendor RGB interface is not accessible. See connection help.');
    if(!device.opened) await device.open();
    this.device=device;device.addEventListener('inputreport',this.report);return true;
  }
  async disconnect() { const device=this.device;this.detach();if(device?.opened)await device.close(); }
  async exchange(packet) {
    if(!this.device?.opened)throw new Error('Connect the keyboard first.');
    const command=packet[1];
    if(packet[0]!==6 || ![5,10,11,20,22].includes(command))throw new Error('Unsupported RGB command blocked.');
    if(this.pending) throw new Error('Another keyboard command is still pending.');
    const report=new Uint8Array(64);report.set(packet);
    return new Promise((resolve,reject)=>{
      const pending={command,resolve,reject,timer:null};
      pending.timer=setTimeout(()=>{if(this.pending===pending){this.pending=null;reject(new Error(`Keyboard did not acknowledge command 0x${command.toString(16)}. Close other RGB apps and retry.`));}},1800);
      this.pending=pending;
      this.device.sendReport(0,report).catch(error=>{if(this.pending===pending){clearTimeout(pending.timer);this.pending=null;reject(error);}});
    });
  }
  async exclusive(fn) {if(this.busy)throw new Error('A keyboard operation is already running.');this.busy=true;try{return await fn();}finally{this.busy=false;}}
  async layout(colors,brightness,onProgress=()=>{}) {
    if(!Number.isInteger(brightness)||brightness<0||brightness>100||keys.some(k=>!/^([a-f0-9]{6})$/i.test(colors[k]??'')))throw new Error('Invalid layout or brightness.');
    return this.exclusive(async()=>{
      await this.exchange([6,5]);let config=await this.exchange([6,10]);
      if(config[7]!==22){
        config=await this.exchange([6,22,0,0,0,1,0,22]);
        if(config[2]!==11||config[7]!==22)throw new Error('Invalid custom lighting template.');
        const mode=new Uint8Array(16);mode.set([6,11,11]);mode.set(config.slice(5,16),5);mode[7]=22;
        if((await this.exchange(mode))[2]!==1)throw new Error('Custom lighting mode was rejected.');
      }
      for(const [i,key] of keys.entries()){
        const offset=keyMap[key]*3,hex=scaled(colors[key],brightness),rgb=hex.match(/../g).map(v=>parseInt(v,16));
        const response=await this.exchange([6,20,3,offset&255,offset>>8,0,0,0,...rgb]);
        if(response[2]!==1 || response[3]!== (offset&255) || response[4]!==offset>>8 || rgb.some((v,j)=>response[8+j]!==v))throw new Error(`Color for ${key} was not confirmed.`);
        onProgress(i+1,keys.length);
      }
    });
  }
  async effect(mode,brightness,speed) {
    if(![0,...Array.from({length:14},(_,i)=>i+2)].includes(mode)||!Number.isInteger(brightness)||brightness<0||brightness>4||!Number.isInteger(speed)||speed<0||speed>3)throw new Error('Invalid firmware effect settings.');
    return this.exclusive(async()=>{
      const config=await this.exchange([6,22,0,0,0,1,0,mode]);
      if(config[2]!==11||config[7]!==mode)throw new Error('Invalid effect template.');
      const packet=new Uint8Array(16);packet.set([6,11,11]);packet.set(config.slice(5,16),5);
      // Preserve FE12's type 1; type 0 silently rejects the write.
      packet[8]=brightness;packet[9]=speed;packet[15]=mode===0?0:[30,80,140,200,236][brightness];
      if((await this.exchange(packet))[2]!==1)throw new Error('Effect write was rejected.');
      const result=await this.exchange([6,10]);
      if(result[7]!==mode||result[8]!==brightness||result[9]!==speed)throw new Error('Effect settings did not match keyboard readback.');
    });
  }
}
