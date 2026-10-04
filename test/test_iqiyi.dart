import 'package:flutter_test/flutter_test.dart';
import 'package:trabekprey_downloader/services/iqiyi_creator_service.dart';

void main() {
  test('test iQIYI stream resolution via IqiyiCreatorService', () async {
    final streamUrl = await IqiyiCreatorService.resolveEpisodeStream('https://www.iqiyi.com/v_xsrdj9xjdw.html');
    print('SUCCESS! Resolved stream: $streamUrl');
    expect(streamUrl != null && streamUrl.isNotEmpty, true);
  });
}
