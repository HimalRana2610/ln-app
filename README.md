# ln-app

Flutter mobile client for LectureNote AI. Talks to [`ln-backend`](../ln-backend);
it holds no business logic of its own.

This is the app that carries the features a browser cannot do — BLE proximity
attendance, native biometrics, background lecture recording.

Setup: **[../SETUP.md](../SETUP.md)**.
All Android Studio work: **[../ANDROID_STUDIO.md](../ANDROID_STUDIO.md)**.
Building a release APK: **[../DEPLOYMENT.md](../DEPLOYMENT.md)**.

## Stack

| Concern | Choice | Why |
| --- | --- | --- |
| State | Riverpod | Compile-safe dependency graph, trivially overridable in tests, no `BuildContext` needed to read state |
| Routing | go_router | One declarative `redirect` gates every route, so a new screen cannot ship unguarded |
| HTTP | Dio | Interceptor pipeline; the silent token refresh is impractical without it |
| Token storage | flutter_secure_storage | Keychain / encrypted Android storage, **not** SharedPreferences |
| Models | freezed + json_serializable | Immutable, value-equal, generated JSON |
| Tests | flutter_test + mocktail | |
| Lints | flutter_lints + strict analyzer | `strict-casts`, `strict-inference`, `strict-raw-types` |

## Layout

Feature-first, not layer-first. Everything about a feature sits in one folder, so
it can be understood — or deleted — without hunting through four directories.

```
lib/
├── main.dart
├── core/                         Cross-cutting infrastructure
│   ├── config/app_config.dart    Build-time configuration
│   ├── network/
│   │   ├── api_client.dart       Dio setup, error mapping
│   │   ├── auth_interceptor.dart Token attach + silent refresh
│   │   ├── api_exception.dart    One error type for the whole app
│   │   └── token_storage.dart    Secure storage wrapper
│   ├── router/app_router.dart    Routes + the auth redirect
│   └── theme/app_theme.dart      Design tokens
├── features/
│   ├── auth/
│   │   ├── data/                 Repository + models
│   │   ├── application/          Controller (Riverpod notifier)
│   │   └── presentation/         Screens + validators
│   ├── dashboard/presentation/
│   └── splash/
└── shared/widgets/               Reusable UI primitives
```

Each feature layers as **presentation → application → data**. Presentation never
touches Dio; data never touches widgets.

## How auth works

1. `login` stores the token pair in secure storage.
2. `AuthInterceptor` attaches `Authorization: Bearer <access>` to every request.
3. On a `401` it refreshes once, then **retries the original request**, so the
   user never sees a failure caused by an expired token.
4. If the refresh fails, storage is cleared and `AuthState` flips to
   unauthenticated — the router redirect then sends the user to `/login`.

Two details in `auth_interceptor.dart` matter more than they look:

**Concurrent 401s are collapsed onto one refresh.** When a token expires,
several in-flight requests fail at once. Without a shared completer each would
start its own refresh, and since the backend *rotates* refresh tokens, the second
one replays an already-used token — which the backend treats as theft and
responds to by revoking every session. The user would be silently logged out for
no reason. One shared `Completer` prevents that.

**The refresh call uses a separate Dio with no interceptors**, so a failing
refresh cannot trigger another refresh.

## Commands

| Command | Purpose |
| --- | --- |
| `flutter pub get` | Install dependencies |
| `dart run build_runner build --delete-conflicting-outputs` | **Required before first run** — generates the model files |
| `dart run build_runner watch -d` | Regenerate on save |
| `flutter devices` | List connected phones |
| `flutter run --dart-define=API_BASE_URL=…` | Run on the connected phone |
| `flutter test` | Run tests — no phone needed |
| `flutter analyze` | Static analysis |
| `dart format lib test` | Format |
| `flutter build apk --release` | Release APK |

## Configuration

All configuration is `--dart-define`, so nothing environment-specific is
committed.

| Define | Default | Notes |
| --- | --- | --- |
| `API_BASE_URL` | `http://10.0.2.2:8000/api/v1` on Android, `http://localhost:8000/api/v1` otherwise | Must include `/api/v1` |

> The Android default `10.0.2.2` is an **emulator-only** alias for the host
> machine. On a physical phone you must pass your PC's LAN address explicitly:
>
> ```bash
> flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000/api/v1
> ```
>
> and start the backend with `--host 0.0.0.0`. Getting this wrong is the single
> most common cause of "Could not reach the server".

In Android Studio, set this once under **Run → Edit Configurations → Additional
run args** so the ▶ button works — see
[../ANDROID_STUDIO.md](../ANDROID_STUDIO.md).

## Conventions

- **Validators mirror the backend** (`validators.dart` ↔ `app/schemas/auth.py`
  ↔ `ln-web`'s Zod schemas). Client validation saves a round trip; it enforces
  nothing. The backend is the control.
- **One error type.** Everything network-related surfaces as `ApiException`, so
  screens never unpick `DioException`.
- **Generated files are gitignored** — run `build_runner` after cloning or
  pulling model changes.
- **`pubspec.lock` is committed** — this is an application, so builds must be
  reproducible.

## Matching the old app's UI

The old client is React + Tailwind; Flutter cannot reuse those classes, so this
is a genuine rewrite rather than a port. The approach:

1. Design tokens are mapped once in `lib/core/theme/app_theme.dart` — the seed
   colour is `#1E293B`, matching the old `themeColor` and splash background.
2. Screens are rebuilt to match visually, compared against the old app by
   screenshot rather than by reading code.

Full token list is in [../docs/PROGRESS.md](../docs/PROGRESS.md).

## Toolchain note

`ln-app` uses **Gradle 9.3.1 with AGP 9.1.0**, which supports JDK 25 — the JDK
that ships with current Android Studio. The "Incompatible Gradle JVM version"
error from the old project does not apply here; that project used Gradle 8.13,
which caps out at JDK 23.

## Android manifest notes

Two Flutter-template defaults are deliberately overridden:

- **`INTERNET` is declared in `src/main/`**, not just `debug/` and `profile/`.
  The template's placement leaves a release APK with no network access at all —
  it installs, launches, and fails every request.
- **`usesCleartextTraffic="true"` is set in `src/debug/` only.** Android blocks
  plain `http://` for apps targeting API 28+, which a LAN backend needs during
  development. Release builds keep the block, so production must be HTTPS.

## Status

Auth, classrooms and notes are complete. **38 tests** passing, `flutter analyze`
clean, Android APK builds.

> `android/gradle.properties` sets `kotlin.incremental=false`: the `file_picker`
> plugin fails to close its Kotlin incremental caches on Windows, aborting the
> build with an `AssertionError` that survives `flutter clean`.

**Verified on a physical device** (Samsung SM M136B, Android 14): sign-in
through to the dashboard, with class cards rendering the same gradients as the
web client.

Materials and assignments are next — see
[../docs/PROGRESS.md](../docs/PROGRESS.md).
