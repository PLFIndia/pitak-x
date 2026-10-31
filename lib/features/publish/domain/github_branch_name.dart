/// A GitHub branch name that is safe in the app's fixed API paths.
library;

/// Validated branch identity used by publishing and pending moves.
///
/// This is deliberately the one branch grammar shared by the domain journal
/// and the HTTP adapter. A branch is never URL-encoded or repaired: unusual
/// characters could select a different API endpoint, so they are refused.
final class GitHubBranchName {
  const GitHubBranchName._(this.value);

  /// The canonical branch spelling.
  final String value;

  /// Parses the existing publish adapter's bounded branch grammar.
  static GitHubBranchName? tryParse(String? raw) {
    if (!isValid(raw)) return null;
    return GitHubBranchName._(raw!);
  }

  /// True when [raw] can be used as a publish branch.
  static bool isValid(String? raw) {
    if (raw == null || !_pattern.hasMatch(raw)) return false;
    return raw
        .split('/')
        .every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }

  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9._/-]{1,200}$');

  @override
  String toString() => 'GitHubBranchName($value)';
}
