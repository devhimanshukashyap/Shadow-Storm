// lib/admin/admin_main.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Entry Point
//
// Run with:
//   flutter run -d chrome -t lib/admin/admin_main.dart
//
// This runs the admin panel completely separately
// from the main app while sharing the same Firebase project.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// Update this import to match your project's firebase_options path
import '../../firebase_options.dart';

import 'auth/admin_auth_guard.dart';
import 'theme/admin_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ShadowStormAdminApp());
}

class ShadowStormAdminApp extends StatelessWidget {
  const ShadowStormAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'Shadow Storm Admin',
      debugShowCheckedModeBanner: false,
      theme:                    buildAdminTheme(),
      home:                     const AdminAuthGuard(),
    );
  }
}