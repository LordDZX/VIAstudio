const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync('index.html', 'utf8');
for (const match of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);
// Execute the real map helpers without connecting to production Supabase.
function source(name) {
  const start = html.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  for (let end = html.indexOf('}', start); end >= 0; end = html.indexOf('}', end + 1)) {
    const candidate = html.slice(start, end + 1);
    try { new vm.Script(`(${candidate})`); return candidate; } catch {}
  }
  throw Error(`Unclosed function: ${name}`);
}
const context = vm.createContext({
  MAP_TYPES: [['sale', '販賣'], ['collaboration', '作品分享'], ['hiring', '徵才']],
  defaults: ['thread', 'plant', 'film', 'bake', 'ceramic', 'paper', ...Array.from({length:18}, (_,i)=>`district-${i+6}`)].map(id=>({id})),
  currentMap: 'sale', shops: [], shopSpots: [], PARKS: [], racks: [], benches: [], npcs: [], remotePlayers: new Map(), player: {x:606,y:586},
});
for (const name of ['normalizeShopType', 'shopType', 'onCurrentMap', 'overlaps', 'placementValidity', 'blockedByBuilding', 'distanceToDoor', 'syncShopPositions']) vm.runInContext(source(name), context);
context.getShop = id => context.shops.find(s=>s.id===id);
assert.equal(context.shopType({shopType:'collaboration',products:[{title:'kept'}]}), 'collaboration');
assert.equal(context.shopType({id:'film',owner:'Existing owner',products:[{}]}), 'sale');
assert.equal(context.normalizeShopType('invalid'), 'sale');
assert.deepEqual(context.defaults.map(s=>context.shopType(s)).reduce((counts,key)=>(counts[key]++,counts),{sale:0,collaboration:0,hiring:0}),{sale:8,collaboration:8,hiring:8});
context.shops = [
  {id:'one',shopType:'sale',position:{x:180,y:200}},
  {id:'two',shopType:'hiring',position:{x:180,y:200}},
];
context.syncShopPositions();
assert.equal(context.shops[1].position.x,180,'different maps may reuse a position');
assert.equal(context.placementValidity('one',180,200,false).ok,true,'other-map shops do not block construction');
context.shops[1].shopType='sale';
assert.equal(context.placementValidity('one',180,200,false).ok,false,'same-map collision rejected');
context.syncShopPositions();
assert.notDeepEqual(context.shops[0].position,context.shops[1].position,'same-map duplicates repaired');
context.currentMap='collaboration';
assert.equal(context.blockedByBuilding(200,250),false,'invisible buildings cannot block walking');
assert.equal(context.distanceToDoor(context.shops[0]),Infinity,'cannot enter other-map doors');
context.currentMap='sale';
assert.equal(context.blockedByBuilding(200,250),true,'visible buildings remain solid');
console.log('PASS: script syntax, legacy classification, 3-map distribution, placement isolation, collision repair, walking and door isolation');

