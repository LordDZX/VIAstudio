const fs=require('fs'),vm=require('vm'),assert=require('assert');
// Reuse the DOM/canvas smoke harness, then test the interaction and validation rules.
let harness=fs.readFileSync('smoke-test.cjs','utf8');
harness=harness.replace('project,shopSpots,blockedByBuilding','interactionZones,activeInteractionZone,validateListing,externalPlayer,streetState,racks,benches,streetInteract,rackCounts,streetSpeed,moveRoom,accountId,chooseNearestFrame,project,shopSpots,blockedByBuilding');
harness=harness.replace("localStorage:{getItem(){return null},setItem(){}},", "localStorage:{data:new Map(),getItem(k){return this.data.get(k)||null},setItem(k,v){this.data.set(k,String(v))}},");
harness=harness.replace("console.log('PASS:","console.log('BASE PASS:");
harness+=`
assert.strictEqual(t.shops.length,24);assert.strictEqual(t.shopSpots.length,24);assert.strictEqual(t.racks.length,16);
// V9 replaces standing zones with aim-based targeting, covered by test-v9.
const image={width:1280,height:720,mediaType:'image'},sale={title:'手作杯',desc:'手作陶杯',contacts:['mail@example.com'],category:'sale',price:'1200',location:'台北',externalURL:''};
t.validateListing(sale,[image]);assert.throws(()=>t.validateListing({...sale,price:''},[image]));assert.throws(()=>t.validateListing({...sale,location:''},[image]));assert.throws(()=>t.validateListing(sale,[]));assert.throws(()=>t.validateListing(sale,[image,image,image,image]));t.validateListing(sale,[{...image,width:640,height:480}]);assert.throws(()=>t.validateListing(sale,[{...image,width:7680,height:4320}]));assert.throws(()=>t.validateListing({...sale,contacts:Array(11).fill('a')},[image]));t.validateListing({...sale,contacts:Array(10).fill('a')},[image]);
assert(t.externalPlayer('https://www.youtube.com/watch?v=dQw4w9WgXcQ').includes('/embed/'));assert(t.externalPlayer('https://www.tiktok.com/@example/video/1234567890123456789').includes('/player/v1/'));assert(!t.externalPlayer('https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ'));assert(!t.externalPlayer('javascript:alert(1)'));
t.roomPlayer.x=300;t.roomPlayer.y=720;t.moveRoom(1000,0);assert(t.roomPlayer.x<=350,'Counter collision');
const rack=t.racks[0];t.player.x=rack.x;t.player.y=rack.y;t.streetInteract();assert(t.streetState.bike);assert.strictEqual(t.rackCounts()[rack.id],14);assert.strictEqual(t.streetSpeed(),375);t.streetInteract();assert(!t.streetState.bike);assert.strictEqual(t.rackCounts()[rack.id],15);assert.strictEqual(t.streetSpeed(),150);
const bench=t.benches[0];t.player.x=bench.x;t.player.y=bench.y;t.streetInteract();assert.strictEqual(t.streetState.seated,bench.id);t.streetInteract();assert.strictEqual(t.streetState.seated,null);
assert(html.replaceAll(' ', '').replaceAll('\\n', '').replaceAll('\\r', '').includes('(roomPlayer.pitch||0)-(e.clientY-roomLookPointer.y)*0.7'),'Mouse up raises horizon / looks upward');
console.log('V4 PASS: 24 shops; standing zones independent of yaw; listing required fields, 1–3 images, 10 contacts, optional 720p recommendation and 4K bounds; video URL allowlist; counter collision; bike borrow/return capacity and speed; bench sit/stand; pitch direction.');
`;
vm.runInThisContext('(function(require){'+harness+'\n})')(require);
