import 'package:farmitra_nearby/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A clean checkout has no shared Firebase project or database', () {
    expect(DefaultFirebaseOptions.apiKey, isEmpty);
    expect(DefaultFirebaseOptions.projectId, isEmpty);
    expect(DefaultFirebaseOptions.databaseUrl, isEmpty);
    expect(DefaultFirebaseOptions.isConfigured, isFalse);
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
  });
}
