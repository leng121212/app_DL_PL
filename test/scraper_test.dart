import 'package:flutter_test/flutter_test.dart';
import 'package:trabekprey_downloader/models/drama_models.dart';
import 'package:trabekprey_downloader/services/hongguo_service.dart';

void main() {
  test('Platform models have correct display names', () {
    expect(PlatformType.hongguo.displayName, contains('Hongguo'));
    expect(PlatformType.reelshort.displayName, equals('ReelShort'));
    expect(PlatformType.mydrama.displayName, equals('MyDrama'));
    expect(PlatformType.reelsdizim.displayName, equals('ReelsDizim'));
    expect(PlatformType.eightmovie.displayName, equals('8Movie'));
  });

  test('Hongguo categories list is valid', () {
    final cats = HongguoService.getCategories();
    expect(cats.isNotEmpty, isTrue);
    expect(cats.first['id'], equals('all'));
  });
}
