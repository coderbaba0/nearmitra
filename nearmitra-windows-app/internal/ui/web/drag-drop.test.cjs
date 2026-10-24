const {test}=require('node:test'),assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs');
function browser(response={ok:true,json:async()=>({file:'a.txt',message:{id:'sent-1',file_name:'a.txt',peer_id:'phone',mine:true,status:'Sent'}})}) {
 const requests=[],toasts=[],wan=[],overlay={style:{display:'flex'}};
 const ctx={console,Blob,File,FormData,ArrayBuffer,NearMitraChat:require('./chat-routing.js'),NearMitraCall:require('./nearby-call.js'),NearMitraAudioCapture:require('./audio-capture.js'),localStorage:{getItem:()=>null,setItem(){}},document:{addEventListener(){},getElementById:id=>id==='chatDropOverlay'?overlay:null,querySelectorAll:()=>[]},window:{addEventListener(){}},performance:{now:()=>0},setInterval:()=>0,clearInterval(){},setTimeout:()=>0,clearTimeout(){},fetch:async(url,options)=>{requests.push({url,options});return typeof response==='function'?response():response;},toasts,wan};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);
 const run=code=>vm.runInContext(code,ctx);
 run("showToast=message=>toasts.push(message);renderChatMessages=()=>{};savePersistedMessages=()=>{};streamFileOverWan=async(file,id,name)=>wan.push({file,id,name});appState.peers=[{id:'phone',internet_device_id:'wan-phone',ip:'192.168.1.6',name:'Phone'}];appState.activePeer=appState.peers[0]");
 function event(files=[new File(['hello'],'a.txt')]){return {dataTransfer:{files},preventDefault(){this.prevented=true},stopPropagation(){this.stopped=true}}}
 return {run,requests,toasts,wan,overlay,event,drop:async(e,home=false)=>{ctx.dropEvent=e;await run((home?'handleDropFile':'handleChatDrop')+'(dropEvent)')}};
}
test('chat and home drops upload to selected LAN peer and use server message',async()=>{
 for(const home of [false,true]){const b=browser(),e=b.event();await b.drop(e,home);assert.ok(e.prevented&&e.stopped);assert.equal(b.overlay.style.display,'none');assert.equal(b.requests.length,1);assert.equal(b.requests[0].url,'/api/send-file-upload?ip=192.168.1.6');assert.equal(await b.requests[0].options.body.get('file').text(),'hello');assert.equal(b.run('appState.messages.length'),1);assert.equal(b.run('appState.messages[0].id'),'sent-1');assert.equal(b.run('appState.messages[0].status'),'Sent');}
});
test('offline device never uploads and clearly reports offline',async()=>{
 const b=browser();b.run('appState.peers[0].is_online=false');await b.drop(b.event());assert.equal(b.requests.length,0);assert.equal(b.wan.length,0);assert.match(b.toasts.at(-1),/Phone is offline/);assert.equal(b.run('appState.messages.length'),0);
});
test('all dropped files stay targeted to initial peer if chat changes',async()=>{
 let b;b=browser(()=>{b.run("appState.activePeer={id:'other',ip:'192.168.1.8'}");return {ok:true,json:async()=>({})}});await b.drop(b.event([new File(['a'],'a.txt'),new File(['b'],'b.txt')]));assert.equal(b.requests.length,2);assert.ok(b.requests.every(r=>r.url.endsWith('ip=192.168.1.6')));assert.deepEqual(b.requests.map(r=>r.options.body.get('file').name),['a.txt','b.txt']);
});
test('local route preferred; WAN drop streams every file when LAN unavailable',async()=>{
 const b=browser();b.run("appState.wanState={internet_mode_enabled:true,trusted_devices:[{id:'wan-phone',is_online:true}]};appState.activePeer={id:'wan-phone',is_wan:true,name:'Phone'}");await b.drop(b.event());assert.equal(b.requests.length,1);assert.equal(b.wan.length,0);b.requests.length=0;b.run('appState.peers=[]');await b.drop(b.event([new File(['a'],'a.txt'),new File(['b'],'b.txt')]));assert.equal(b.requests.length,0);assert.equal(b.wan.length,2);assert.ok(b.wan.every(item=>item.id==='wan-phone'));
});
test('missing recipient, empty drop and failed upload never create sent messages',async()=>{
 const b=browser();b.run('appState.activePeer=null');await b.drop(b.event());assert.match(b.toasts.at(-1),/select a device/i);b.run('appState.activePeer=appState.peers[0]');await b.drop(b.event([]));assert.match(b.toasts.at(-1),/No files/);assert.equal(b.requests.length,0);
 const failed=browser({ok:false,text:async()=>'Peer disconnected'});await failed.drop(failed.event());assert.match(failed.toasts.at(-1),/Peer disconnected/);assert.equal(failed.run('appState.messages.length'),0);
});
