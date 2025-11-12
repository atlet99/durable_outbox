/// Generates a standard idempotency key header name.
String get idempotencyKeyHeader => 'Idempotency-Key';

/// Validates idempotency key format.
bool isValidIdempotencyKey(String? key) {
  if (key == null || key.isEmpty) {
    return false;
  }
  // Basic validation: non-empty, reasonable length
  return key.length <= 256;
}
