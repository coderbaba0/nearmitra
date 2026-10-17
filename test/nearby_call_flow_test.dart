import 'package:farmitra_nearby/models/chat_route.dart';
import 'package:farmitra_nearby/models/peer.dart';
import 'package:farmitra_nearby/models/wan_models.dart';
import 'package:farmitra_nearby/services/call_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:farmitra_nearby/services/nearby_service.dart';
import 'package:farmitra_nearby/services/socket_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final calls=CallService();
 final native=<MethodCall>[];
 setUp(()async{
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('flutter_callkit_incoming'),(call)async{native.add(call);return null;});
  calls.setCallActive(false);calls.clearPendingIncomingCall();calls.isAppInForeground=true;native.clear();
 });
 tearDown(()async{calls.setCallActive(false);await calls.endAllCalls();});
 test('Nearby Windows and Wi-Fi Direct allow calls; WAN-only and relayed mesh do not',(){
  final desktop=Peer(id:'lan',name:'Laptop',ip:'192.168.49.1',platform:'windows',internetDeviceId:'wan');
  final wanEntry=Peer(id:'wan',name:'Laptop',ip:'',platform:'windows');
  final remote=WanDevice(id:'wan',name:'Laptop',platform:'windows',isOnline:true,isTrusted:true);
  for(final entry in [desktop,wanEntry]){expect(ChatRoute.resolve(entry,[desktop],[remote],{'lan':'wan'},internetEnabled:true).canCall,isTrue);}
  expect(ChatRoute.resolve(wanEntry,[],[remote],{},internetEnabled:true).canCall,isFalse);
  desktop.isMeshPeer=true;expect(ChatRoute.resolve(wanEntry,[desktop],[remote],{'lan':'wan'},internetEnabled:true).canCall,isFalse);
 });
 test('Foreground Windows invite becomes visible without relying on native CallKit notification',()async{
  expect(await calls.showIncomingCall(peerId:'desktop',peerName:'Windows PC',peerIp:'192.168.1.2',isVideoCall:true),isTrue);
  expect(calls.incomingCall.value?.peer.ip,'192.168.1.2');expect(calls.incomingCall.value?.isVideo,isTrue);
  expect(native.where((c)=>c.method=='showCallkitIncoming'),isEmpty);
  var accepted=0;calls.registerCallAcceptedCallback((peer,video,incoming){expect(peer.id,'desktop');expect(video,isTrue);expect(incoming,isTrue);accepted++;});
  calls.acceptPendingIncomingCall();calls.acceptPendingIncomingCall();expect(accepted,1);expect(calls.incomingCall.value,isNull);expect(calls.isCallActive,isTrue);
 });
 test('Busy active call cannot be replaced by a new incoming peer',()async{
  calls.setCallActive(true);expect(await calls.showIncomingCall(peerId:'other',peerName:'Other',peerIp:'192.168.1.8',isVideoCall:false),isFalse);expect(calls.incomingCall.value,isNull);
 });
 test('Duplicate invitation preserves one pending call; unrelated caller is rejected',()async{
  await calls.showIncomingCall(peerId:'desktop',peerName:'PC',peerIp:'192.168.1.2',isVideoCall:false);final pending=calls.incomingCall.value;
  expect(await calls.showIncomingCall(peerId:'desktop',peerName:'PC',peerIp:'192.168.1.2',isVideoCall:false),isTrue);expect(identical(calls.incomingCall.value,pending),isTrue);
  expect(await calls.showIncomingCall(peerId:'other',peerName:'Other',peerIp:'192.168.1.8',isVideoCall:false),isFalse);expect(identical(calls.incomingCall.value,pending),isTrue);
 });
 test('Background native incoming notification gets a valid UUID and exact Nearby target',()async{
  calls.isAppInForeground=false;
  await calls.showIncomingCall(peerId:'desktop',peerName:'PC',peerIp:'192.168.1.2',isVideoCall:true);
  final notification=native.singleWhere((c)=>c.method=='showCallkitIncoming');final args=notification.arguments as Map;
  expect(args['id'],matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  expect((args['extra'] as Map)['peerIp'],'192.168.1.2');
 });
 test('Real Windows-format TCP invite reaches mobile incoming UI and acknowledges ringing',()async{
  final service=NearbyService(deviceId:'mobile-test',deviceName:'Phone');
  final server=await ServerSocket.bind(InternetAddress.loopbackIPv4,0);
  server.listen(service.handleIncomingConnection);
  final socket=await Socket.connect(InternetAddress.loopbackIPv4,server.port);
  final reader=SocketReader(socket);
  try {
   socket.write('${jsonEncode({'type':'call_invite','sender':'Windows Laptop','sender_id':'desktop-id','call_type':'video','is_video':true,'require_ack':true})}\n');await socket.flush();
   final response=jsonDecode((await reader.readLine().timeout(const Duration(seconds:3)))!) as Map;
   expect(response['type'],'call_ringing');expect(response['status'],'ringing');
   expect(calls.incomingCall.value?.peer.name,'Windows Laptop');expect(calls.incomingCall.value?.isVideo,isTrue);
  }finally{await reader.cancel();socket.destroy();await server.close();service.dispose();}
 });

}
