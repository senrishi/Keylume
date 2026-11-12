// Adapts Keylume's isolated native desktop bridge to the editor's HID transport.
export function desktopHID(bridge=globalThis.window?.keylumeDesktop) {
  if(!bridge)return null;
  const listeners=new Map(),deviceListeners=new Map();
  const fire=(registry,type,event)=>{for(const callback of registry.get(type)??[])callback(event);};
  const add=(registry,type,callback)=>{if(!registry.has(type))registry.set(type,new Set());registry.get(type).add(callback);};
  const device={opened:false,collections:[{usagePage:0xFF00,usage:2,outputReports:[{items:[{}]}]}],
    open:async()=>{await bridge.connect();device.opened=true;},
    close:async()=>{await bridge.disconnect();device.opened=false;},
    sendReport:async(id,bytes)=>{if(id!==0)throw new Error('Unsupported report ID.');await bridge.send(Array.from(bytes));},
    addEventListener:(type,callback)=>add(deviceListeners,type,callback),
    removeEventListener:(type,callback)=>deviceListeners.get(type)?.delete(callback)
  };
  bridge.onReport(bytes=>{const buffer=Uint8Array.from(bytes);fire(deviceListeners,'inputreport',{data:new DataView(buffer.buffer)});});
  bridge.onDisconnect(()=>{device.opened=false;fire(listeners,'disconnect',{device});});
  return {requestDevice:async()=>{await device.open();return [device];},addEventListener:(type,callback)=>add(listeners,type,callback)};
}
