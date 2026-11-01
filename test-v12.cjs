const fs = require('node:fs');
const vm = require('node:vm');
let harness = fs.readFileSync('test-v7.cjs', 'utf8');
harness = harness.replace('stableDirection,validateMediaCounts', 'saveMediaBlob,stableDirection,validateMediaCounts');
harness = harness.replace("console.log('V7 PASS:", `
assert(!html.includes('id="listingVideo"'));
assert(!html.includes('accept="video/'));
assert(!nodes.get('#modalContent').innerHTML.includes('value="file"'));
assert.throws(() => t.validateMediaCounts([{mediaType:'video',file:{type:'video/mp4'}}],''));
t.validateMediaCounts([{mediaType:'video',mediaKey:'existing-video'}],'');
t.validateMediaCounts([{mediaType:'image'}],'https://www.youtube.com/watch?v=mIoA-XUMCEQ');
Promise.all([
  assert.rejects(t.saveMediaBlob('test',{type:'video/mp4',name:'clip.mp4'}),/外部影片網址/),
  assert.rejects(t.saveMediaBlob('test',{type:'application/octet-stream',name:'clip.MOV'}),/外部影片網址/)
]).then(()=>console.log('V12 PASS: video upload UI removed, new video files rejected before storage, existing videos and external links retained.')).catch(e=>{console.error(e);process.exitCode=1});
console.log('V7 PASS:`);
vm.runInThisContext('(function(require){' + harness + '\n})')(require);
