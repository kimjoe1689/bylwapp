class SusResponse {
  const SusResponse(this.answers);

  final List<int> answers;

  double? get score {
    if (answers.length != 10 || answers.any((item) => item < 1 || item > 5)) {
      return null;
    }
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += i.isEven ? answers[i] - 1 : 5 - answers[i];
    }
    return 2.5 * sum;
  }
}

const susPrompts = [
  '我愿意经常使用这个床旁采集应用。',
  '我觉得这个应用不必要地复杂。',
  '我觉得这个应用容易使用。',
  '我需要技术人员的帮助才能使用它。',
  '我发现各项功能整合得很好。',
  '我觉得这个应用前后不一致。',
  '我觉得大多数人能很快学会使用它。',
  '我觉得使用起来很别扭。',
  '我使用时很有信心。',
  '我需要先学很多东西才能开始用。',
];
