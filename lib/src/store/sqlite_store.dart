// Conditional implementation: use IO version if available, otherwise use stub
export 'sqlite_store_stub.dart'
    if (dart.library.io) 'sqlite_store_impl_io.dart';
