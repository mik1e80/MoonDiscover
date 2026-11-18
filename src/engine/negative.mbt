///|
/// Valid IN NSEC evidence for a single name/type/scope; never authentication.
pub fn Engine::is_negative(
  self : Engine,
  scope : String,
  name : @model.DnsName,
  rr_type : Int32,
) -> Bool {
  self.cache.is_negative(scope, name, rr_type)
}
