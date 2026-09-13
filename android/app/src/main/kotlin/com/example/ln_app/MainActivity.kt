package com.example.ln_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt as a fragment, and fails with "no_fragment_activity" on a
// plain FlutterActivity. Attendance cannot be marked without it.
class MainActivity : FlutterFragmentActivity()
