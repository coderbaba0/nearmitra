const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function setup(fetcher,launch=true){
 const calls=[];const ctx={console,document:{addEventListener(){},getElementById:id=>id==='chkLaunchApp'?{checked:launch}:null},window:{close(){calls.push('closed');}},alert:message=>calls.push(message),fetch:async(url,options)=>{calls.push({url,options});return fetcher?fetcher(url,options):new Response('{}');}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(__dirname+'/app.js','utf8'),ctx);return {ctx,calls};
}
test('Finish uses implemented backend endpoint and sends launch preference',async()=>{
 for(const launch of [true,false]){const f=setup(null,launch);await vm.runInContext('finishInstaller()',f.ctx);assert.equal(f.calls[0].url,'/api/installer/finish');assert.equal(JSON.parse(f.calls[0].options.body).launch_now,launch);assert.equal(f.calls[1],'closed');}
});
test('Finish failure remains open with a visible error',async()=>{
 const f=setup(async()=>new Response('App could not launch',{status:500}));await vm.runInContext('finishInstaller()',f.ctx);assert.ok(!f.calls.includes('closed'));assert.match(f.calls[1],/could not launch/);
});
test('Cancel uses implemented endpoint and cannot interrupt extraction',async()=>{
 const f=setup();await vm.runInContext('closeInstaller()',f.ctx);assert.equal(f.calls[0].url,'/api/installer/cancel');const g=setup();vm.runInContext('currentStep=3',g.ctx);await vm.runInContext('closeInstaller()',g.ctx);assert.equal(g.calls.length,1);assert.match(g.calls[0],/wait/);
});
