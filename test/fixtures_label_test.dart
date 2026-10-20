import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/ui/screens/fixtures_tab.dart';

void main() {
  test('labels knockout rounds from the bracket size', () {
    expect(knockoutRoundName(1, 6), 'Round of 64');
    expect(knockoutRoundName(2, 6), 'Round of 32');
    expect(knockoutRoundName(5, 6), 'Semi-finals');
    expect(knockoutRoundName(6, 6), 'Final');
    expect(knockoutRoundName(1, 2), 'Semi-finals');
    expect(knockoutRoundName(1, 1), 'Final');
  });
}
