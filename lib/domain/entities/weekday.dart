enum Weekday {
  monday(1, '월'),
  tuesday(2, '화'),
  wednesday(3, '수'),
  thursday(4, '목'),
  friday(5, '금'),
  saturday(6, '토'),
  sunday(7, '일');

  final int value;
  final String label;

  const Weekday(this.value, this.label);
}

