import 'package:deeplinknow/deeplinknow.dart';
import 'package:flutter/material.dart';

/// Your public key (`dln_pub_…`). Pass it at build time:
/// `flutter run --dart-define=DLN_API_KEY=dln_pub_xxx`
const apiKey = String.fromEnvironment('DLN_API_KEY');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

/// The first-launch flow: initialize, ask for the deferred link once, route to it.
class ExampleApp extends StatefulWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  String _status = 'Starting…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // 1. One call to initialize. Never throws: null means it failed (see lastError).
    final info = await DeepLinkNow.initialize(apiKey,
        config: const DLNConfig(enableLogs: true));
    if (info == null) {
      _setStatus('Init failed: ${DeepLinkNow.lastError}');
      return;
    }

    // 2. One call to get the deferred link. Delivered once per install; null afterwards.
    await _checkDeferred();
  }

  Future<void> _checkDeferred({bool force = false}) async {
    final link = await DeepLinkNow.checkDeferredDeepLink(force: force);
    if (link == null) {
      final error = DeepLinkNow.lastError;
      _setStatus(error == null ? 'No deferred link' : 'Check failed: $error');
      return;
    }
    // Fingerprint matches are best effort: decide how much to trust them.
    if (link.source == DeferredDeepLinkSource.fingerprint &&
        link.confidenceScore < ConfidenceThresholds.medium) {
      _setStatus('Ignored a LOW fingerprint match (${link.confidenceScore})');
      return;
    }
    _setStatus(
        'Deferred link from ${link.source.value} (${link.matchQuality.value})');
    _navigatorKey.currentState
        ?.pushNamed(link.path, arguments: link.queryParams);
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  /// Plain Navigator routing on the link's path.
  Route<void> _route(RouteSettings settings) {
    final path = settings.name ?? '/';
    final query = settings.arguments as Map<String, QueryValue>? ?? const {};
    final segments = Uri(path: path).pathSegments;
    final Widget page;
    if (path == '/') {
      page = HomeScreen(onForceCheck: () => _checkDeferred(force: true));
    } else if (segments.length == 2 && segments.first == 'products') {
      page = ProductScreen(id: segments[1], query: query);
    } else {
      page = LinkScreen(path: path, query: query);
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepLinkNow example',
      navigatorKey: _navigatorKey,
      onGenerateRoute: _route,
      builder: (context, child) => _StatusScope(status: _status, child: child!),
    );
  }
}

class _StatusScope extends InheritedWidget {
  const _StatusScope({required this.status, required super.child});

  final String status;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StatusScope>()?.status ?? '';

  @override
  bool updateShouldNotify(_StatusScope oldWidget) => oldWidget.status != status;
}

/// Home: status, plus debug actions.
class HomeScreen extends StatelessWidget {
  /// Creates the screen.
  const HomeScreen({super.key, required this.onForceCheck});

  /// Runs the check again, ignoring the first-launch flag.
  final VoidCallback onForceCheck;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepLinkNow')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_StatusScope.of(context), key: const Key('status')),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: onForceCheck,
              child: const Text('Check again (force)')),
          OutlinedButton(
            onPressed: DeepLinkNow.resetDeferredDeepLink,
            child: const Text('Reset first-launch state'),
          ),
        ],
      ),
    );
  }
}

/// A product page opened from `/products/<id>`.
class ProductScreen extends StatelessWidget {
  /// Creates the screen.
  const ProductScreen({super.key, required this.id, required this.query});

  /// Product id from the path.
  final String id;

  /// Query parameters from the link.
  final Map<String, QueryValue> query;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Product $id')),
      body: _QueryList(query: query),
    );
  }
}

/// Any other path.
class LinkScreen extends StatelessWidget {
  /// Creates the screen.
  const LinkScreen({super.key, required this.path, required this.query});

  /// The link path.
  final String path;

  /// Query parameters from the link.
  final Map<String, QueryValue> query;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(path)),
      body: _QueryList(query: query),
    );
  }
}

class _QueryList extends StatelessWidget {
  const _QueryList({required this.query});

  final Map<String, QueryValue> query;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final entry in query.entries)
          ListTile(
              title: Text(entry.key),
              subtitle: Text(entry.value.stringValues.join(', '))),
      ],
    );
  }
}
