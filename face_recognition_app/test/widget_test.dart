import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:face_recognition_app/main.dart';
import 'package:face_recognition_app/models/registered_face.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.registerAdapter(RegisteredFaceAdapter());
  });

  testWidgets('HomeScreen shows correct titles', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceRecognitionApp());
    await tester.pump();

    expect(find.text('FACE ID'), findsOneWidget);
    expect(find.text('Facial\nRecognition'), findsOneWidget);
    expect(find.text('Recognize'), findsOneWidget);
    expect(find.text('Register Face'), findsOneWidget);
    expect(find.text('Manage Faces'), findsOneWidget);
  });

  testWidgets('HomeScreen has three action cards', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceRecognitionApp());
    await tester.pump();

    expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
  });
}
