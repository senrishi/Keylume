import {mkdir,copyFile,cp} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
for(const file of ['index.html','style.css','app.js','preset.js','driver.js','desktop-hid.js','logo.svg','layout.js','presets.json','rs.json','LICENSE-presets.txt','attribution.txt']) await copyFile(file,`dist/${file}`);
console.log('Static app ready in apps/web/dist');
