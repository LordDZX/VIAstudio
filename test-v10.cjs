const fs=require('fs'),vm=require('vm');let h=fs.readFileSync('smoke-test.cjs','utf8');
h=h.replace('project,shopSpots,blockedByBuilding','PARKS,parkFacilities,useParkFacility,stopParkRide,updateParkRide,get parkRide(){return parkRide},streetInteract,racks,musicFadeGain,set musicFadeStart(v){musicFadeStart=v},endLease,accountId,defaultRoom,placementValidity,project,shopSpots,blockedByBuilding');
h+=`
assert.strictEqual(t.PARKS.length,2);for(const p of t.PARKS){assert.strictEqual(p.w*p.h,1080*1100*2);assert.strictEqual(t.racks.filter(r=>r.id.startsWith(p.id+'-park')).length,2);assert(!t.placementValidity(t.shops[0].id,p.x+200,p.y+200).ok)}
assert.strictEqual(new Set(t.parkFacilities.map(f=>f.kind)).size,6);for(const f of t.parkFacilities){t.player.x=f.x;t.player.y=f.y;t.streetInteract();assert.strictEqual(t.parkRide.facility.id,f.id);t.updateParkRide(.5);assert(Math.hypot(t.player.x-f.x,t.player.y-f.y)>1);t.streetInteract();assert.strictEqual(t.parkRide,null)}
t.musicFadeStart=1000;assert.strictEqual(t.musicFadeGain(1000),0);assert.strictEqual(t.musicFadeGain(3500),.5);assert.strictEqual(t.musicFadeGain(6000),1);t.musicFadeStart=null;
const shop=t.shops[0],a=t.shopSpots[0];shop.lease.ownerId=t.accountId;shop.boardText='old';shop.boardColor='#ff0000';shop.music={tracks:[]};shop.room.wallColor='#ff0000';assert(t.endLease(shop));assert(!shop.destroyed&&!shop.lease&&!shop.boardText&&!shop.music&&!shop.boardColor);assert.strictEqual(shop.room.wallColor,t.defaultRoom().wallColor);assert(t.blockedByBuilding(a.x+100,a.y+80));assert.strictEqual(t.endLease(shop),false);
assert(html.includes('name="boardColor"'));assert(!html.includes("['Facebook','f']"));console.log('V10 PASS: doubled parks, six rides, park racks and placement limits, retained rental house, reset interiors, board color, five-second fade.');
`;
vm.runInThisContext('(function(require){'+h+'\n})')(require);
