# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-01-13

### Changed

- Replaced `sqflite` with `sqlite3` package for pure Dart support
- Removed `path_provider` dependency to enable pure Dart compatibility
- Improved `drain()` method to process all queued entries, not just up to concurrency limit
- Enhanced `markFailed()` logic: entries with `nextAttempt` are now marked as `queued` for retry instead of `failed`

### Fixed

- Fixed `drain()` method to work correctly when scheduler is not running (`autoStart: false`)
- Fixed retry logic: failed entries with retry schedule are now properly requeued
- Fixed test timing issues with retry backoff delays

### Added

- Comprehensive dartdoc documentation for public API (20%+ coverage)
- Example file (`example/example.dart`) for pub.dev package requirements
- Improved API documentation with usage examples

## [0.1.0] - 2025-01-13

### Added

- Core API with `DurableOutbox` facade
- `OutboxStore` interface with SQLite and Memory implementations
- `OutboxTransport` interface with HTTP implementation
- `RetryPolicy` with Decorrelated Jitter Backoff
- Idempotency key support
- Pause/Resume functionality
- Watch streams for queue state and counts
- Basic metrics support
- Foreground runtime with scheduler
- Examples and tests

### Features

- Offline queue with guaranteed delivery
- Automatic retry with configurable backoff
- Priority-based processing
- Delayed start support (`notBefore`)
- Channel-based queue organization
- Cross-platform support (mobile, desktop, web)

