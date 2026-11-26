import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/app/app.dart';
import 'package:rentflow/core/config/env_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = EnvConfig.fromEnvironment();
  if (env.isConfigured) {
    await Supabase.initialize(
      url: env.supabaseUrl,
      publishableKey: env.supabaseAnonKey,
    );
  }
  runApp(const ProviderScope(child: RentFlowApp()));
}
