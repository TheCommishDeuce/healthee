/// The two interceptors on the app's dio client: the session and the logging.
///
/// Split from `api_client.dart` so the client file stays about wiring and these
/// stay about policy (Standards §1: one reason to change per file).
library;

import 'package:dio/dio.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/auth/identity_client.dart';

/// Applies the owner's stored server session — the address AND the right token.
///
/// Both, in one interceptor, because they are one fact: the credential was
/// accepted by *that* server and is meaningless at any other. Applying them from
/// two places would allow the combination this app must never build — one
/// server's credential sent to a different host.
///
/// ## Two credentials, chosen by path
///
/// ```text
///   /ingest/*  →  the device token   (long-lived, from the keystore)
///   /api/*     →  the Supabase JWT   (about an hour, refreshed on demand)
/// ```
///
/// They are not interchangeable and the server accepts each on exactly one of
/// the two paths. The split exists because background BLE sync runs on a phone
/// that has been asleep for six hours, and an access token that lives for one
/// cannot be what a push presents (MULTI_USER.md §4.3).
///
/// **A missing JWT sends NO header rather than falling back to the device
/// token.** The fallback is the tempting line and it is wrong twice: `/api/*`
/// does not accept a device token, so it buys nothing; and it would turn "your
/// session expired, sign in again" into an indistinguishable 401 that the app
/// would keep retrying with a credential that cannot work.
///
/// ## The transitional path
///
/// An owner who signed in by PASTING a token — the only thing this app could do
/// before Supabase sign-in existed — has a stored token and no identity. That
/// token goes on both paths, exactly as it always did, because it is the shared
/// `REALTIME_INGEST_TOKEN` and the server still accepts it on both. It is the
/// branch that disappears when that secret is retired, and nothing else here
/// changes when it does.
///
/// The base URL only overrides `Env.apiBaseUrl` when a session is stored, so a
/// build's dart-define stays the default and a phone with no session behaves
/// exactly as before. `RequestOptions.uri` is a getter over `baseUrl + path`
/// (dio 5.11 `options.dart`), so setting it here is what the request goes to.
///
/// Reading per-request rather than caching at construction is deliberate:
/// sign-in, sign-out and moving to a different server all take effect on the
/// next call with no invalidation step. Secure-storage reads are a
/// platform-channel hop, not a network one, and they are off the render path.
///
/// **Nothing here is logged.** The token goes into a header and never into a log
/// line, a URL or a query — `test/signin/signin_secrecy_test.dart` drives the
/// app's real client through this interceptor and fails if it ever appears.
class ServerSessionInterceptor extends Interceptor {
  /// Reads the session from [credentials] and the JWT from [identity].
  ///
  /// [identity] is null on a build with no configured identity provider, which
  /// is the self-hoster who never made a Supabase project. Every `/api/*` call
  /// then falls to the stored token, which is what that build has.
  ServerSessionInterceptor(this._credentials, this._identity);

  final Credentials _credentials;
  final IdentityClient? _identity;

  /// The prefix whose requests carry the DEVICE token.
  static const String ingestPrefix = '/ingest/';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final session = options.extra.containsKey(CacheSession.requestKey)
        ? options.extra[CacheSession.requestKey] as StoredServerSession?
        : await _credentials.serverSession();
    if (session == null) {
      handler.next(options);
      return;
    }
    options.baseUrl = session.baseUrl;
    final credential = await _credentialFor(options.path, session);
    if (credential != null) {
      options.headers['Authorization'] = 'Bearer $credential';
    }
    handler.next(options);
  }

  /// Which credential this path takes, or null when there is none to send.
  ///
  /// Null is a real answer and not a failure: an expired session whose refresh
  /// did not succeed has no token, and sending the wrong one instead would only
  /// change which 401 the owner gets.
  Future<String?> _credentialFor(String path, StoredServerSession session) async {
    // `/ingest/*` takes the stored credential whichever kind it is: the server
    // accepts a device token there, and it accepts the shared one there too.
    if (path.startsWith(ingestPrefix)) {
      return session.token;
    }
    // An enrolled phone's own token is accepted on BOTH paths by design
    // (`docs/QR_ENROLLMENT.md`); there is no identity session behind it.
    if (session.kind == StoredCredentialKind.enrolled) {
      return session.token;
    }
    // ⛔ The transitional path. The shared token is the one credential the
    // server takes on BOTH, and it is what a phone mid-migration holds.
    if (session.kind == StoredCredentialKind.shared) {
      return session.token;
    }
    // A device token was minted, so an identity minted it. `/api/*` takes the
    // JWT and nothing else — a device token there is a 401 by design, so when
    // there is no live JWT the honest thing to send is no header at all. That
    // 401 is what `SessionGuardInterceptor` turns into "sign in again"; a
    // credential that cannot work would be a 401 the app replays forever.
    return _identity?.accessToken();
  }
}

/// Logs every request, response and failure through the one logging path.
///
/// Bodies are omitted unless `--dart-define=HELIO_LOG_HTTP=true`: a response here
/// is somebody's health data, and it should not end up in a device log because a
/// developer wanted a status code. The status, method, path and duration are
/// always logged, because those are what you need to answer "is it slow or is it
/// broken" and none of them are personal.
class ApiLogInterceptor extends Interceptor {
  /// [logBodies] should come from `Env.logHttpBodies`.
  ApiLogInterceptor({required this.logBodies});

  /// Whether to include request/response bodies in the log.
  final bool logBodies;

  static const String _startedAtKey = 'startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    AppLog.info('api', '→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final path = response.requestOptions.path;
    AppLog.info(
      'api',
      '← ${response.statusCode} $path ${_elapsed(response.requestOptions)}'
          '${logBodies ? ' ${response.data}' : ''}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Logged, then passed on — never swallowed (Standards §1). The repository
    // above turns this into a typed failure the UI can render with a retry.
    //
    // ⚠ The raw `DioException` goes to the logger, and it is safe against the
    // dio we pin: its `toString` emits `type`, `message` and `error` only, and
    // no factory message quotes the URI or the headers. `pubspec.yaml` pins a
    // CARET range, so a future minor could change that format without a change
    // here — which means **the guard is the test, not the pin**.
    // `test/signin/signin_secrecy_test.dart` drives this exact interceptor
    // stack with `AppLog.sink` capturing, including a 401 whose body echoes the
    // token, and fails if the credential appears anywhere in the transcript.
    // It is what has to survive a dependency bump; do not delete it as
    // redundant with this comment.
    AppLog.failure(
      'api',
      '${err.requestOptions.method} ${err.requestOptions.path} failed '
          '${_elapsed(err.requestOptions)}',
      err,
      err.stackTrace,
    );
    handler.next(err);
  }

  String _elapsed(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! DateTime) {
      return '';
    }
    return 'in ${DateTime.now().difference(startedAt).inMilliseconds}ms';
  }
}


/// Ends a session the server has stopped accepting (auth audit C4).
///
/// ## What this closes
///
/// `Credentials.forgetServerSession` had exactly one caller: the sign-out
/// button. A 401 did four things and none of them was that — it dropped the
/// affected cache rows and rethrew, rendered *"Sign in to your server to use
/// this feature"*, suppressed the retry, and reported a push failure — while
/// `ServerSessionStatus.signedIn` went on returning true.
///
/// So a revoked, rotated or expired credential left the app in the state
/// `server_session.dart`'s own docstring says the design exists to prevent:
/// believing it is signed in, serving 401s to every screen, and re-sending the
/// dead credential on every screen load and every background sync, with nothing
/// ever prompting a re-authentication. Revocation would have shipped and not
/// visibly worked.
///
/// ## Marked, not cleared
///
/// [onRejected] is expected to mark the session as needing attention rather than
/// delete it. The gentler option is enough — the owner is asked once instead of
/// silently looping — and clearing would throw away the server address they
/// typed, so the re-sign-in would start from a blank field.
///
/// ## Only 401, and only from `/api/*`
///
/// 403 is deliberately NOT here. It means the server knows exactly whose
/// credential this is and will not serve that account — a suspension, or a
/// paywall — and signing the owner out over it would replace an accurate
/// message with a login screen that changes nothing.
///
/// `/ingest/*` is excluded because a push runs headless in a background isolate:
/// there is nobody to prompt, the device token is a separate credential with its
/// own lifetime, and revoking a phone's ingest token must not sign the owner out
/// of the app on that phone before they can see why.
class SessionGuardInterceptor extends Interceptor {
  /// [onRejected] is called once per rejected request; it must be cheap.
  SessionGuardInterceptor(this._onRejected);

  final void Function() _onRejected;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    if (status == 401 && !path.startsWith(ServerSessionInterceptor.ingestPrefix)) {
      // The status and the path. Never the header, and never the body — a 401
      // body is the server's refusal and can quote what was presented.
      AppLog.info('signin', 'the server rejected this session (401 on $path)');
      _onRejected();
    }
    handler.next(err);
  }
}