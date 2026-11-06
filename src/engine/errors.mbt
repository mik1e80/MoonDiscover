///|
pub impl Show for EngineError with fn output(self, logger) {
  logger.write_string(
    match self {
      Closed => "engine_closed"
      InvalidServiceType =>
        "invalid_service_type: expected a local DNS-SD type/instance"
      ResourceLimit(detail) => "resource_limit: " + detail
      UnknownSubscription => "unknown_subscription"
      RateLimited => "ingress_rate_limited"
      InvalidTime => "invalid_ingress_time"
    },
  )
}

///|
#deprecated
pub extend EngineError with Show::{to_string, output}
