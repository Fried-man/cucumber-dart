import 'package:test/test.dart';

import '../example/cucumber_ci_environment_example.dart';

void main() {
  test('the example describes a GitHub Actions build', () {
    expect(
      describeCiEnvironment({
        'GITHUB_SERVER_URL': 'https://github.com',
        'GITHUB_REPOSITORY': 'cucumber-ltd/shouty.rb',
        'GITHUB_RUN_ID': '154666429',
        'GITHUB_SHA': '99684bcacf01d95875834d87903dcb072306c9ad',
        'GITHUB_HEAD_REF': 'main',
        'GITHUB_EVENT_NAME': 'push',
      }),
      'GitHub Actions: '
      'https://github.com/cucumber-ltd/shouty.rb/actions/runs/154666429 '
      '(build 154666429)\n'
      'https://github.com/cucumber-ltd/shouty.rb.git at '
      '99684bcacf01d95875834d87903dcb072306c9ad, main',
    );
  });

  test('the example reports when no CI server is detected', () {
    expect(describeCiEnvironment({}), 'No CI server detected.');
  });
}
