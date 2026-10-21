import 'package:deeplinknow/deeplinknow.dart';
import 'package:deeplinknow_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <String>[];

  void mockNative(Object? deferredLink) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeepLinkNow.channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return {
            'id': 'app_1',
            'alias': 'myapp',
            'domains': ['myapp.deeplinknow.com'],
            'primaryDomain': 'myapp.deeplinknow.com',
            'accountStatus': 'active',
          };
        case 'checkDeferredDeepLink':
          return deferredLink;
      }
      return null;
    });
  }

  testWidgets(
      'FLT-20 first launch: initialize, check once, route to the deferred path',
      (tester) async {
    mockNative({
      'path': '/products/123',
      'queryParams': {'ref': 'newsletter'},
      'fullPath': '/products/123?ref=newsletter',
      'url': 'https://myapp.deeplinknow.com/products/123?ref=newsletter',
      'source': 'clipboard',
      'confidenceScore': 100,
      'matchQuality': 'HIGH',
    });

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(calls, ['initialize', 'checkDeferredDeepLink']);
    expect(find.text('Product 123'), findsOneWidget);
    expect(find.text('newsletter'), findsOneWidget);
  });

  testWidgets('FLT-20 no deferred link: stays on the home screen',
      (tester) async {
    mockNative(null);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('No deferred link'), findsOneWidget);
  });
}
