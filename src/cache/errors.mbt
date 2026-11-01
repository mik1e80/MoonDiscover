///|
pub impl Show for CacheError with fn output(self, logger) {
  logger.write_string(
    match self {
      InvalidTime => "invalid_time: non-monotonic or overflowing clock"
      InvalidScope => "invalid_scope: length outside 1..256"
      CapacityExceeded => "cache_capacity_exceeded"
      InvalidRecord(detail) => "invalid_record: " + detail
    },
  )
}

///|
#deprecated
pub extend CacheError with Show::{to_string, output}
