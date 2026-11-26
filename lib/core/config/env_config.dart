/// Environment configuration read via `--dart-define`.
///
/// Security rule (`AGENTS.md`): Never place Supabase service-role secrets in
/// Flutter code or app bundles.
class EnvConfig {
  const EnvConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory EnvConfig.fromEnvironment() {
    const url = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'http://127.0.0.1:54321',
    );
    const anonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );
    validatePublishableKey(anonKey);
    return const EnvConfig(
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void validatePublishableKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized.contains('service_role') ||
        normalized.startsWith('sb_secret_')) {
      throw StateError(
        'Refusing to initialize with a Supabase service_role or secret key.',
      );
    }
  }
}
