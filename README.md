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
│   ├── config/
│   │   ├── app_config.dart       Build-time configuration
│   │   └── server_url.dart       Address parsing and normalization
│   ├── network/
│   │   ├── api_client.dart       Dio setup, error mapping
│   │   ├── auth_interceptor.dart Token attach + silent refresh
│   │   ├── api_exception.dart    One error type for the whole app
│   │   ├── server_locator.dart   Finds the backend on this network
│   │   ├── server_connection.dart The address in use, and its state
│   │   ├── server_storage.dart   Remembers the address that worked
│   │   └── token_storage.dart    Secure storage wrapper
│   ├── router/app_router.dart    Routes + the auth redirect
│   └── theme/app_theme.dart      Design tokens
├── features/
│   ├── auth/
│   │   ├── data/                 Repository + models
│   │   ├── application/          Controller (Riverpod notifier)
│   │   └── presentation/         Screens + validators
│   ├── dashboard/presentation/
│   ├── settings/presentation/    The server picker
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
| `flutter run` | Run on the connected phone — the server is found automatically |
| `flutter test` | Run tests — no phone needed |
| `flutter analyze` | Static analysis |
| `dart format lib test` | Format |
| `flutter build apk --release` | Release APK |

## Finding the server

**You do not need to configure an address.** The app finds the backend itself,
because a development machine on DHCP does not keep one: the address changes
when the lease renews, when the laptop moves between Wi-Fi and Ethernet, and
whenever you join another network. Baking one in at build time meant a rebuild
every time that happened.

`ServerLocator` searches in two stages, cheapest first:

| Stage | Tried |
| --- | --- |
| Known addresses | The one that worked last time · `API_BASE_URL` if given · `localhost` (works over `adb reverse`) · `10.0.2.2` (emulator) |
| Sweep | Every address on the phone's own /24, tested for an open port 8000 and then confirmed with a real `/health` call |

The confirming call matters: other devices on a home network answer on port
8000, and only a correct `{"status": "ok"}` identifies ours. Whatever is found
is remembered, so later launches skip straight to it, and a request that cannot
reach the server triggers one fresh search and a retry — a changed address
heals itself mid-session instead of surfacing as an error.

The address is also shown on the login screen and in the dashboard app bar,
where **Change** opens a picker to type one in or re-run the search. That is the
fallback for a network where devices cannot see each other, such as a campus
Wi-Fi with client isolation.

Start the backend with `--host 0.0.0.0` so it accepts connections from the
phone at all.

### Configuration

All configuration is `--dart-define`, so nothing environment-specific is
committed.

| Define | Default | Notes |
| --- | --- | --- |
| `API_BASE_URL` | none | Optional. Seeds the search — tried first, then discovery takes over if it does not answer. Must include `/api/v1` |
| `API_PORT` | `8000` | The port the sweep looks for |

Set `API_BASE_URL` only for a deployed backend, where there is nothing on the
local network to find.

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
