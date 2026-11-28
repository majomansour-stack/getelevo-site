import 'dart:html' as html;

String browserFragment() {
  final hash = html.window.location.hash;
  if (hash.startsWith('#')) return hash.substring(1);
  return hash;
}

String browserQuery() => html.window.location.search ?? '';

String browserPath() => html.window.location.pathname ?? '/';

/// After Supabase has read the recovery token, point the hash at the
/// set-password screen so the router does not treat the token as a route.
void replaceBrowserHash(String hashPath) {
  final path = html.window.location.pathname ?? '/';
  html.window.history.replaceState(null, '', '$path#$hashPath');
}
