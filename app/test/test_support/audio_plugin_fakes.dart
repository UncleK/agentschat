import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _recordMethodChannel = MethodChannel(
  'com.llfbandit.record/messages',
);

void installAudioPluginMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordMethodChannel, (call) async {
        switch (call.method) {
          case 'create':
          case 'start':
          case 'startStream':
          case 'pause':
          case 'resume':
          case 'cancel':
          case 'dispose':
            return null;
          case 'hasPermission':
            return false;
          case 'isPaused':
          case 'isRecording':
            return false;
          case 'stop':
            return null;
          case 'getAmplitude':
            return <String, double>{'current': 0, 'max': 0};
          case 'isEncoderSupported':
            return true;
          case 'listInputDevices':
            return const <Map<String, Object?>>[];
          default:
            return null;
        }
      });
}

void removeAudioPluginMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_recordMethodChannel, null);
}
