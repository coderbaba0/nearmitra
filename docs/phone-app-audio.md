# Phone-to-phone app audio (unreleased source)

The Wi-Fi Audio Speaker action now accepts an Android phone as the audio source.
It captures permitted app playback, rather than substituting the source phone's
microphone. The existing PC WebRTC audio and microphone paths remain separate.

## Use

1. Install updated source builds on both Android phones and connect them through
   Nearby or Wi-Fi Direct.
2. On the listening phone, open Streaming → Wi-Fi Audio → Speaker, select the
   other phone and choose **Listen to phone audio**.
3. On the source phone, allow the NearMitra request, grant Android's audio
   permission if asked, and approve the system capture consent dialog.
4. Play music/video on the source phone. The listening phone uses its media
   volume and can adjust playback volume, select its speaker/earpiece where
   supported, or stop. Either phone can stop the session.

Android calls the required permission `RECORD_AUDIO`; this implementation uses
`AudioPlaybackCaptureConfiguration`, with no microphone source or video/display
capture. Android may show its standard screen/capture consent UI because the
permission token is a MediaProjection token.

Playback capture on the source requires **Android 10+**, capture-compatible audio
usages/apps and the same user profile. Apps can prohibit capture. Protected
content and voice-call audio are not guaranteed to be available. See
[Android playback capture requirements](https://developer.android.com/media/platform/av-capture).
Silence from a restricted app is not replaced by microphone audio.

## Implementation and verification

The existing wireless request/approval messages negotiate `android_pcm_v1` only
between updated phones. Native workers transfer fixed 48 kHz stereo PCM16 over
a direct TCP socket. Playback preserves frame alignment across fragmented TCP
reads; bounded buffers and blocking native writes supply backpressure. The
temporary receiver checks the expected peer address and a fresh random token.
Audio bytes do not traverse the Dart UI isolate. Meter events are limited to
twice per second, and a stalled connection is stopped rather than left live.

Automated checks cover two-phone signalling/approval, no microphone fallback,
denial, cancellation during capture consent, duplicate offers, format validation,
projection revocation, PCM framing/levels and the existing PC/microphone tests.

Physical-device validation is still required: permitted music/video playback,
permission denial/cancellation, source app switching, stop on either side, Wi-Fi
loss/reconnect, volume/routing, and a subsequent PC audio/microphone/video call.
Tests and compilation do not establish audible quality or latency on real phones.
