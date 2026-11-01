///|
pub using @model {type DnsName, type TxtRecord, type TxtValue, type InputError}

///|
pub using @engine {
  type Engine,
  type Event,
  type ServiceSnapshot,
  type SrvCandidate,
  type EngineError,
  type EngineStats,
}

///|
pub using @wire {
  type Message,
  type Question,
  type Record,
  type RData,
  type Section,
  type WireError,
}

///|
pub fn decode_packet(data : Bytes) -> Message raise WireError {
  @wire.decode(data)
}

///|
pub fn qm_query(name : DnsName, rr_type : Int32) -> Bytes raise WireError {
  @wire.qm_query(name, rr_type)
}
