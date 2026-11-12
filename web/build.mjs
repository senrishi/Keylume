import {mkdir,copyFile,cp} from 'node:fs/promises';
await mkdir('dist',{recursive:true});
for(const file of ['index.html','style.css','app.js','preset.js','driver.js','layout.js','presets.json','rs.json','LICENSE-presets.txt','attribution.txt']) await copyFile(file,`dist/${file}`);
console.log('Static app ready in web/dist');
