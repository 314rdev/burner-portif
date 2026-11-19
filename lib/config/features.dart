/// Build-time feature flags, set with `--dart-define` or in
/// `config/firebase.env.json`.
class Features {
  const Features._();

  /// Shows "Create an account" on the sign-in screen. Off for now: accounts
  /// are created in the Firebase console. Turn on with
  /// `"BURNER_SIGNUP_ENABLED": "true"`.
  ///
  /// Hiding the button doesn't stop someone calling the sign-up API directly;
  /// also disable sign-ups in Firebase Authentication → Settings → User actions.
  static const signUpEnabled = bool.fromEnvironment('BURNER_SIGNUP_ENABLED');
}
