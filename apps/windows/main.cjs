const {app,BrowserWindow,Menu,Tray,ipcMain,protocol,net,shell,nativeImage}=require('electron');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const HID=require('node-hid');
const {HIDBridge}=require('./hid-bridge.cjs');
protocol.registerSchemesAsPrivileged([{scheme:'keylume',privileges:{standard:true,secure:true,supportFetchAPI:true}}]);
let window,tray,quitting=false;
const uiRoot=path.join(__dirname,'ui');
const bridge=new HIDBridge(HID,(type,data)=>{if(window&&!window.isDestroyed())window.webContents.send('rgb:'+type,data);});
function checkSender(event){if(!window||event.sender!==window.webContents||event.senderFrame!==window.webContents.mainFrame||!event.senderFrame.url.startsWith('keylume://studio/'))throw new Error('Untrusted IPC sender.');}
function show(){window.show();window.focus();}
function external(url){try{const u=new URL(url);if(u.protocol==='https:'&&['developer.chrome.com','github.com'].includes(u.hostname))shell.openExternal(u.href);}catch{}}
if(!app.requestSingleInstanceLock())app.quit();else {
app.setName('Keylume');
app.on('second-instance',()=>{if(window)show();});
app.whenReady().then(async()=>{
  if(process.argv.includes('--self-test')) {
    try {
      const fs=require('node:fs');
      const catalog=JSON.parse(fs.readFileSync(path.join(uiRoot,'presets.json'),'utf8'));
      if(catalog.length!==140)throw new Error('Missing preset catalog.');
      for(const name of ['index.html','app.js','driver.js','desktop-hid.js','logo.svg'])fs.accessSync(path.join(uiRoot,name));
      fs.accessSync(path.join(__dirname,'assets/Keylume.ico'));
      const devices=await HID.devicesAsync(0x36AE,0xFE12);
      const result={ok:true,version:app.getVersion(),platform:process.platform,nativeHID:true,presetCount:catalog.length,connectedInterfaces:devices.length};
      const i=process.argv.indexOf('--self-test-report');if(i>=0&&process.argv[i+1])fs.writeFileSync(process.argv[i+1],JSON.stringify(result));
      console.log(JSON.stringify(result));app.exit(0);return;
    } catch(error){console.error(error);app.exit(1);return;}
  }
  protocol.handle('keylume',request=>{
    const url=new URL(request.url);
    if(url.host!=='studio')return new Response('Not found',{status:404});
    let decoded;try{decoded=decodeURIComponent(url.pathname);}catch{return new Response('Bad request',{status:400});}
    const file=path.resolve(uiRoot,'.'+(decoded==='/'?'/index.html':decoded));
    if(!file.startsWith(uiRoot+path.sep))return new Response('Forbidden',{status:403});
    return net.fetch(pathToFileURL(file).href);
  });
  window=new BrowserWindow({width:1340,height:920,minWidth:800,minHeight:660,title:'Keylume',backgroundColor:'#101218',icon:path.join(__dirname,'assets/logo.png'),webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,webSecurity:true}});
  window.webContents.session.setPermissionRequestHandler((_,__,callback)=>callback(false));
  window.webContents.setWindowOpenHandler(({url})=>{external(url);return {action:'deny'};});
  window.webContents.on('will-navigate',(event,url)=>{if(!url.startsWith('keylume://studio/')){event.preventDefault();external(url);}});
  window.on('close',event=>{if(!quitting){event.preventDefault();window.hide();}});
  window.webContents.on('render-process-gone',()=>bridge.disconnect().catch(()=>{}));
  window.webContents.on('did-fail-load',(_,code,description)=>console.error('UI failed to load:',code,description));
  ipcMain.handle('rgb:connect',async event=>{checkSender(event);return bridge.connect();});
  ipcMain.handle('rgb:send',async(event,packet)=>{checkSender(event);await bridge.write(packet);});
  ipcMain.handle('rgb:disconnect',async event=>{checkSender(event);await bridge.disconnect();});
  Menu.setApplicationMenu(null);
  tray=new Tray(nativeImage.createFromPath(path.join(__dirname,'assets/tray.png')));
  tray.setToolTip('Keylume · MK1300 V2 RGB');
  tray.setContextMenu(Menu.buildFromTemplate([{label:'Open Keylume',click:show},{type:'separator'},{label:'Quit Keylume',click:()=>app.quit()}]));
  tray.on('double-click',show);
  window.loadURL('keylume://studio/index.html');
});
app.on('activate',()=>{if(window)show();});
app.on('before-quit',()=>{quitting=true;bridge.disconnect().catch(()=>{});});
app.on('window-all-closed',()=>{if(quitting)app.quit();});
}
