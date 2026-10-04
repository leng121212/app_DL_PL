import 'package:flutter_test/flutter_test.dart';
import 'package:trabekprey_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TrabekpreyDownloaderApp());
    expect(find.byType(TrabekpreyDownloaderApp), findsOneWidget);
  });
}
