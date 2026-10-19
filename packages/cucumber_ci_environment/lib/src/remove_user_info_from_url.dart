/// Removes the user name and password from [value] when it is a URL, such as
/// `https://user:token@gitlab.com/group/project.git`.
///
/// Some CI servers put credentials in the variable that holds the Git remote.
/// Values that are not URLs with user information are returned unchanged.
String removeUserInfoFromUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.userInfo.isEmpty) {
    return value;
  }
  return uri.replace(userInfo: '').toString();
}
