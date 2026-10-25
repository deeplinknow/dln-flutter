/// DeepLinkNow deferred deep linking for Flutter: a thin wrapper over the native iOS and
/// Android SDKs.
library;

export 'src/deeplinknow.dart' show DeepLinkNow;
export 'src/errors.dart';
export 'src/link.dart' hide schemeOf, schemePathOf, stripDlnFragment, systemSchemes;
export 'src/types.dart' hide DLNShapeException;
