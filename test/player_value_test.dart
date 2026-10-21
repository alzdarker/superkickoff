import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';

void main() {
  test('overall increase never lowers a valuable player market value', () {
    final int value = SquadRepository.valueAfterOverallChange(
      currentValue: 60000000,
      previousPower: 81,
      newPower: 82,
      age: 24,
    );

    expect(value, greaterThan(60000000));
    expect(value, 63000000);
  });
}
