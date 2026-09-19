/// The ONLY place in this app that reads a `--dart-define`.
///
/// Engineering Standards §3 is explicit: "All dart-defines live in
/// `core/env.dart`". Not "mostly"; the rule is worth the file because
/// `String.fromEnvironment` is a **compile-time** read — it silently returns the
/// default when the define is missing, so a second call site with a mistyped key
/// does not fail, it just quietly gets the empty string. One file means one place
/// to read to know what this build was configured with, and one place to grep
/// before a release.
///
/// If you are adding a build-time knob, it goes here. If you are reaching for
/// `String.fromEnvironment` anywhere else, the answer is no.
///
/// ## What is deliberately NOT here: `MAC` and `AUTHKEY`
///
/// The legacy app took the strap's Bluetooth MAC address and its pairing
/// AUTHKEY as dart-defines, baked at build time. That single decision is what
/// made it a single-owner app: the binary *was* the pairing. A second person
/// could not use a build without recompiling it, and the owner's own key shipped
/// inside every APK.
///
/// Both values come from the Zepp account at pairing time and are per-owner
/// secrets. They live in the platform keystore via `flutter_secure_storage`
/// (`data/api/credentials.dart`), written once when the strap is paired and read
/// by the BLE layer. The same goes for the API bearer token: `HELIO_TOKEN` is
/// *not* a define here either, because a token compiled into a build is a token
/// that cannot be rotated without a release.
///
/// The rule that follows: **a dart-define may describe the build; it may never
/// identify the owner.** Anything owner-specific is runtime state in secure
/// storage. That is the whole difference between the legacy app and this one.
library;

/// Build-time configuration. All fields are compile-time constants.
///
/// Not injectable and not a provider on purpose — these values cannot change
/// while the app runs, and wrapping a `const` in a provider would suggest they
/// can. Runtime configuration (the paired strap, the signed-in owner, the
/// selected theme) is Riverpod state; this is not that.
abstract final class Env {
  /// Base URL of the Healthee API, e.g. `https://healtheeapi.example.com`.
  ///
  /// Defaults to the loopback address a debug build talks to when the server is
  /// running from `infra/docker-compose.yml` on the same machine. It is a
  /// LOCAL-ONLY default on purpose: a release build that forgets `--dart-define`
  /// should fail to reach anything, loudly, rather than quietly aim at prod.
  static const String apiBaseUrl = String.fromEnvironment(
    'HELIO_API',
    defaultValue: 'http://127.0.0.1:8765',
  );

  /// The owner's Supabase project URL, e.g. `https://abcd.supabase.co`.
  ///
  /// Supabase is this product's identity provider and **nothing else**: it signs
  /// the access JWT, the server verifies it, and no part of this app ever talks
  /// to Supabase's database, storage or realtime. That is why the dependency is
  /// `gotrue` alone and not `supabase_flutter`, which brings twenty-four
  /// packages to reach three endpoints.
  ///
  /// Blank — the default — means **this build has no sign-in**, and the sign-in
  /// screen says so rather than offering a form that cannot work. A self-hoster
  /// who has not created a Supabase project is in exactly that state, and it is
  /// not a failure: they still pair a strap and read every screen from the local
  /// store, which is the strap-only mode this app has always supported.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The Supabase project's **anon** key. Publishable by design.
  ///
  /// ⚠ The `anon` key, never the `service_role` key. The anon key identifies the
  /// project and authorises nothing on its own — it is meant to ship inside
  /// clients, and Supabase's own docs say so. The service-role key bypasses
  /// every policy and belongs only on a server; the backend keeps its own under
  /// `SUPABASE_SERVICE_ROLE_KEY` and this app must never see it.
  ///
  /// This is the one place a `String.fromEnvironment` holds something that looks
  /// like a secret and is not one, so it is worth the paragraph: the rule this
  /// file opens with — a define may describe the build, never identify the owner
  /// — still holds. The project is the build. The owner is the session, and the
  /// session lives in the keystore.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// True when this build was given a Supabase project to sign in against.
  ///
  /// Both or neither: half a configuration is a form that submits into a 400,
  /// and the screen would report the owner's password as the problem.
  static bool get hasIdentityProvider =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Where basemap tiles come from, when that is not [apiBaseUrl].
  ///
  /// Blank — the default and the normal case — means the app asks its OWN
  /// server, the one it is signed into, and the tiles ride the same session and
  /// the same bearer token as every other call. That is the whole architecture:
  /// the phone never talks to a tile provider, because a tile request says where
  /// somebody is looking, and the server proxies and caches so the provider
  /// learns a square of the world instead of an owner's neighbourhood.
  ///
  /// Set it (`--dart-define=HELIO_TILES=https://maps.example.com`) to point the
  /// basemap at a different Healthee-compatible host — a build talking to a
  /// laptop API but wanting the VPS's warm tile cache, say. A host named here is
  /// NOT the signed-in server, so nothing sends it the owner's session: no base
  /// URL override, no `Authorization` header. That is the rule this file opens
  /// with, in its other direction — a define may describe the build, and it may
  /// never carry, or leak, a secret.
  static const String tileBaseUrl = String.fromEnvironment('HELIO_TILES');

  /// True when tiles come from a host that is not the signed-in server.
  static bool get hasSeparateTileHost => tileBaseUrl.isNotEmpty;

  /// How long a single API call may take before it is an error.
  ///
  /// Standards §1 budgets server read endpoints at p95 < 100 ms, so ten seconds
  /// is not a latency target — it is the point past which the network is not
  /// coming back and the UI should say so instead of spinning forever.
  static const Duration requestTimeout = Duration(
    seconds: int.fromEnvironment('HELIO_TIMEOUT_S', defaultValue: 10),
  );

  /// How long one `POST /ingest/helio` may take.
  ///
  /// Deliberately far longer than [requestTimeout], and the legacy client's
  /// comment says why in the voice of the person it happened to: a multi-day
  /// backlog is a big body **and** a server-side multi-day re-derive, "30 s was
  /// too short, so the sync kept timing out and the backlog never cleared". A
  /// backlog that can never clear is a permanent hole in the owner's history,
  /// which is a worse failure than a slow request.
  ///
  /// The push is paged, so this bounds a page rather than a whole catch-up.
  static const Duration pushTimeout = Duration(
    seconds: int.fromEnvironment('HELIO_PUSH_TIMEOUT_S', defaultValue: 180),
  );

  /// How long one `POST /api/coach` may take.
  ///
  /// The coach is the one call in this app that pays for its own latency. The
  /// server's gate charges one of the owner's twenty included questions **before
  /// the handler starts**, deliberately, so it cannot be raced — which means a
  /// client that hangs up early does not cancel anything. It leaves the server
  /// producing an answer, charging for it, matching none of the four refund
  /// branches (a *delivered* answer is neither refused, nor unvalidated, nor an
  /// exception, nor a greeting), and returning 200 to a socket nobody is reading.
  /// The owner pays $0.179 and one of twenty, and sees a failure.
  ///
  /// [requestTimeout] is therefore the wrong budget for it, and not by a little:
  /// ten seconds is derived from a p95 < 100 ms *read* target, while one coach
  /// turn is bounded at `insights.coach.GATHERING_ROUNDS` (20) tool rounds plus
  /// the pipeline's reserved answer attempts, each at the server's own 60 s
  /// `llm_timeout_s`.
  ///
  /// ## 180 s was measured against the wrong questions
  ///
  /// It was sized on "narrow questions were measured converging in two rounds",
  /// which is true and was the wrong sample. Timed against the owner's own broad
  /// question — *"What should I notice about my sleep?"* — on the live coach tier:
  ///
  ///     80.1s  82.4s  131.7s  169.3s  276.7s  304.1s
  ///     median 169.3 s · max 304.1 s
  ///
  /// **Two of six exceeded 180 s and the median sat on the line.** A broad question
  /// fans out into more gathering rounds than a narrow one, so the old budget threw
  /// away roughly a third of the answers it had already paid for — the failure this
  /// docstring's first paragraph describes, arriving through the number meant to
  /// prevent it.
  ///
  /// Those numbers are history. The server was re-measured on 2026-09-19 after
  /// routing its coach model to fast providers, streaming every completion under a
  /// 120 s wall-clock deadline, and sending passages instead of whole notes: coach
  /// mean 27 s, p95 48 s, worst 62 s over 90 questions; two live production
  /// questions took 53 s and 76 s. 180 s clears all of that with headroom.
  ///
  /// With the streamed endpoint this is the gap the client tolerates BETWEEN bytes,
  /// and the server sends a keepalive every 10 s while it works, so a healthy turn
  /// never approaches it; it bounds the non-streaming fallback and a genuinely dead
  /// stream. Making the wait *legible* is the composer's job (it shows the server's
  /// own stages); this constant's only duty is to not discard work that was charged
  /// for.
  ///
  /// It is its OWN knob rather than a reuse of [pushTimeout] because the two
  /// numbers answer different questions — a multi-day sync backlog and a model
  /// thinking — and a shared constant would make one of them silently follow the
  /// other's next revision, even when the two happen to agree, as they do today.
  static const Duration coachTimeout = Duration(
    seconds: int.fromEnvironment('HELIO_COACH_TIMEOUT_S', defaultValue: 180),
  );

  /// Whether to log every HTTP request/response body.
  ///
  /// Off unless asked for, in every build type. Response bodies here are somebody's
  /// health data, and `--dart-define=HELIO_LOG_HTTP=true` is a deliberate act.
  static const bool logHttpBodies = bool.fromEnvironment('HELIO_LOG_HTTP');

  /// True when the app was built without being told where the server is.
  ///
  /// Surfaced on the sync-health screen rather than thrown: a build misconfigured
  /// this way still runs against the local cache, and telling the owner why the
  /// network is silent beats a crash on launch.
  static bool get isUsingFallbackApi => apiBaseUrl == 'http://127.0.0.1:8765';
}
