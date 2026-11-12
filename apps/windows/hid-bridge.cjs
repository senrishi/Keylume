// Native access is restricted to the MK1300 V2 RGB configuration interface.
function validateReport(packet) {
  if(!Array.isArray(packet)||packet.length!==64||packet.some(v=>!Number.isInteger(v)||v<0||v>255)||packet[0]!==6)throw new Error('Invalid HID report.');
  const command=packet[1];
  if(![5,10,11,20,22].includes(command))throw new Error('Command is outside the RGB allowlist.');
  if(command===11&&(packet[2]!==11||packet[5]!==1||![0,...Array.from({length:14},(_,i)=>i+2),22].includes(packet[7])||packet[8]>4||packet[9]>4))throw new Error('Invalid lighting configuration.');
  if(command===20&&(packet[2]!==3||packet[3]+256*packet[4]>219||(packet[3]+256*packet[4])%3!==0))throw new Error('Invalid per-key color offset.');
  if(command===22&&(packet[5]!==1||![0,...Array.from({length:14},(_,i)=>i+2),22].includes(packet[7])))throw new Error('Invalid effect template request.');
  return packet;
}
class HIDBridge {
  constructor(HID,emit) { this.HID=HID;this.emit=emit;this.device=null;this.opening=false; }
  async connect() {
    if(this.device)return true;
    if(this.opening)throw new Error('A connection is already in progress.');
    this.opening=true;
    try {
      const devices=(await this.HID.devicesAsync(0x36AE,0xFE12)).filter(d=>d.usagePage===0xFF00&&d.usage===2);
      if(devices.length!==1)throw new Error(devices.length?'Connect only one MK1300 V2 keyboard.':'MK1300 V2 RGB interface not found. Plug in the keyboard and close other RGB software.');
      const device=await this.HID.HIDAsync.open(devices[0].path);
      this.device=device;
      device.on('data',data=>{if(this.device!==device)return;const bytes=Array.from(data);if(bytes.length===65&&bytes[0]===0)bytes.shift();if(bytes.length===64&&bytes[0]===0xAA)this.emit('report',bytes);});
      device.on('error',()=>{if(this.device===device){this.device=null;device.close().catch(()=>{});this.emit('disconnect');}});
      return true;
    } finally {this.opening=false;}
  }
  async write(packet) {
    validateReport(packet);
    if(!this.device)throw new Error('Keyboard is disconnected.');
    // HIDAPI always needs a leading report ID, including report ID 0.
    await this.device.write([0,...packet]);
  }
  async disconnect() { const device=this.device;this.device=null;if(device)await device.close(); }
}
module.exports={HIDBridge,validateReport};
