const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function browser(fetcher=async()=>new Response('{}')){
 const elements=new Map();const ctx={console,Response,performance:{now:()=>0},NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),localStorage:{getItem:()=>null,setItem:()=>{}},document:{addEventListener:()=>{},getElementById:id=>elements.get(id)||null,querySelectorAll:()=>[]},window:{addEventListener:()=>{}},setInterval:()=>0,clearInterval:()=>{},setTimeout,clearTimeout,fetch:fetcher};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);vm.runInContext('showToast=message=>{lastToast=message;}',ctx);
 return {ctx,element:(id,value='')=>{const e={value,style:{},setAttribute(k,v){this[k]=v;},removeAttribute(k){delete this[k];}};elements.set(id,e);return e;},run:code=>vm.runInContext(code,ctx)};
}
test('IoT peer selection has an empty state and preserves selected real peer',()=>{
 const b=browser(),select=b.element('audioCastPeerSelect','192.168.1.4');b.run('populateHwPeerSelects()');assert.ok(select.disabled);assert.ok(!select.innerHTML.includes('192.168.1.7'));
 b.run("appState.peers=[{ip:'192.168.1.4',name:'Phone',is_online:true}];populateHwPeerSelects()");assert.equal(select.value,'192.168.1.4');assert.equal(select.disabled,false);
});
test('IoT broadcast uses the shared call engine and supports both audio sources',async()=>{
 const b=browser();b.element('audioCastPeerSelect','192.168.1.4');b.element('audioCastSourceMode','both');const source=b.element('pcAudioSource','mic');b.run('startCallWithPeer=async(...args)=>{callArgs=args;}');await b.run('toggleLiveAudioMirror()');assert.equal(source.value,'both');assert.equal(b.ctx.callArgs[3],'broadcast');
 b.run("desktopCall.session={mode:'duplex'};callArgs=null");await b.run('toggleLiveAudioMirror()');assert.equal(b.ctx.callArgs,null);assert.match(b.ctx.lastToast,/End the current call/);
});
test('Phone microphone starts a receive-only call without claiming connection',async()=>{
 const b=browser();b.element('remoteMicPeerSelect','192.168.1.4');b.run('startCallWithPeer=async(...args)=>{callArgs=args;}');await b.run('toggleRemoteMicBridge()');assert.equal(b.ctx.callArgs[3],'listen');const badge=b.element('remoteMicBadge');b.run("syncIotAudioState('ringing',{mode:'listen'})");assert.match(badge.innerText,/Waiting/);b.run("syncIotAudioState('connected',{mode:'listen'})");assert.equal(badge.innerText,'Connected');b.run("syncIotAudioState('ended',null)");assert.equal(badge.innerText,'Standby');
});
test('Phone telemetry preserves 0% battery and GPS zero coordinates; stale or different devices clear readings',async()=>{
 let sensors={device_ip:'192.168.1.4',last_seen:new Date().toISOString(),battery_available:true,battery_level:0,gps_locked:true,gps_latitude:0,gps_longitude:0,gps_altitude:0};
 const b=browser(async()=>new Response(JSON.stringify({sensors})));b.element('audioCastPeerSelect','192.168.1.4');const battery=b.element('phoneBatLevelText'),lat=b.element('gpsLatVal'),map=b.element('gpsMapLink');await b.run('pollRemoteSensors()');assert.equal(battery.innerText,'0%');assert.equal(lat.innerText,'0.000000°');assert.match(map.href,/q=0,0/);
 sensors.device_ip='192.168.1.8';await b.run('pollRemoteSensors()');assert.equal(battery.innerText,'—');assert.equal(map.href,undefined);
 sensors.device_ip='192.168.1.4';sensors.last_seen='2020-01-01';await b.run('pollRemoteSensors()');assert.equal(lat.innerText,'—');
});
test('NFC failure displays real error without a success toast',async()=>{
 const b=browser(async()=>new Response('No NFC reader transport is connected',{status:501}));await b.run('triggerNFCRead()');assert.match(b.ctx.lastToast,/No NFC reader/);
});
test('Relay UI waits for acknowledged state and retains unknown after device failure',async()=>{
 let fail=false;const b=browser(async(path,options)=>{assert.equal(path,'/api/iot/toggle');assert.equal(JSON.parse(options.body).state,true);return fail?new Response('relay did not confirm',{status:502}):new Response('{"power":true}');});
 const status=b.element('pumpStatusText');b.element('btnPumpToggle');await b.run('toggleAgriRelay(1)');assert.equal(status.innerText,'[ ON ]');
 b.run('agriRelayStates={}');fail=true;await b.run('toggleAgriRelay(1)');assert.equal(status.innerText,'[ Unknown ]');assert.match(b.ctx.lastToast,/did not confirm/);
});
test('Empty hardware scan shows missing camera and surfaces backend errors',()=>{
 const b=browser(),camera=b.element('listCameraDevices'),status=b.element('hwScanStatus');b.run("renderHardwareDiagnostics({hardware:{scan_error:'Windows hardware query timed out'}})");assert.match(camera.innerHTML,/No camera or scanner/);assert.equal(status.innerText,'Windows hardware query timed out');assert.ok(!camera.innerHTML.includes('Webcam Active'));
});
test('Request sensors uses selected phone and waits for an approved response',async()=>{
 const requests=[];const b=browser(async(path,options)=>{requests.push(path);if(path.endsWith('trigger')){assert.equal(JSON.parse(options.body).target_ip,'192.168.1.4');return new Response('{"sensors":{"location_status":"Location not shared"}}');}return new Response('{"sensors":{}}');});b.element('audioCastPeerSelect','192.168.1.4');const status=b.element('phoneSensorStatus');await b.run('fetchLiveGPS()');assert.equal(status.innerText,'Location not shared');assert.equal(requests.length,2);
});
test('Approved phone location failure explains provider status rather than hiding it behind generic GPS text',async()=>{
 const sensors={device_ip:'192.168.1.4',last_seen:new Date().toISOString(),gps_locked:false,location_status:'Location allowed, but no fresh GPS/network fix arrived'};
 const b=browser(async()=>new Response(JSON.stringify({sensors})));b.element('audioCastPeerSelect','192.168.1.4');const place=b.element('gpsLocName'),status=b.element('phoneSensorStatus'),badge=b.element('gpsLockBadge');
 await b.run('pollRemoteSensors()');assert.equal(place.innerText,sensors.location_status);assert.equal(status.innerText,sensors.location_status);assert.equal(badge.innerText,'Location unavailable');
 sensors.device_ip='192.168.1.8';await b.run('pollRemoteSensors()');assert.equal(place.innerText,'No recent location received');
});
