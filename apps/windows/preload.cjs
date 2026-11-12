const {contextBridge,ipcRenderer}=require('electron');
// No raw IPC, device paths, filesystem, or Node objects are exposed to the page.
contextBridge.exposeInMainWorld('keylumeDesktop',{
  connect:()=>ipcRenderer.invoke('rgb:connect'),
  disconnect:()=>ipcRenderer.invoke('rgb:disconnect'),
  send:packet=>ipcRenderer.invoke('rgb:send',packet),
  onReport:callback=>{const listener=(_,bytes)=>callback(bytes);ipcRenderer.on('rgb:report',listener);return()=>ipcRenderer.removeListener('rgb:report',listener);},
  onDisconnect:callback=>{const listener=()=>callback();ipcRenderer.on('rgb:disconnect',listener);return()=>ipcRenderer.removeListener('rgb:disconnect',listener);}
});
