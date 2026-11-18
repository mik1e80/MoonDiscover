///|
fn append(out : Array[Byte], bytes : Bytes) -> Unit {
  for b in bytes {
    out.push(b)
  }
}

///|
fn put16(out : Array[Byte], n : Int32) -> Unit {
  out.push((n >> 8).to_byte())
  out.push((n & 255).to_byte())
}

///|
fn payload(record : Record) -> Bytes raise WireError {
  match (record.rr_type, record.data) {
    (1, A(bytes)) => {
      guard bytes.length() == 4 else {
        raise Malformed("invalid A known answer")
      }
      bytes
    }
    (28, Aaaa(bytes)) => {
      guard bytes.length() == 16 else {
        raise Malformed("invalid AAAA known answer")
      }
      bytes
    }
    (12, Ptr(name)) => name.to_wire()
    (16, Txt(txt)) => txt.to_wire()
    (47, Nsec(name, bitmap)) => {
      guard bitmap.length() >= 1 &&
        bitmap.length() <= 32 &&
        !nsec_contains(bitmap, 47) else {
        raise Malformed("invalid restricted NSEC")
      }
      let out = name.to_wire().to_array()
      out.push(0)
      out.push(bitmap.length().to_byte())
      append(out, bitmap)
      Bytes::makei(out.length(), i => out[i])
    }
    (33, Srv(priority, weight, port, target)) => {
      guard priority >= 0 &&
        priority <= 65535 &&
        weight >= 0 &&
        weight <= 65535 &&
        port >= 0 &&
        port <= 65535 else {
        raise Malformed("SRV known answer fields outside wire range")
      }
      let bytes : Array[Byte] = []
      put16(bytes, priority)
      put16(bytes, weight)
      put16(bytes, port)
      append(bytes, target.to_wire())
      Bytes::makei(bytes.length(), i => bytes[i])
    }
    _ => raise Malformed("unsupported/mismatched known answer")
  }
}

///|
/// A single bounded QM query. Oversized Known-Answer sets return an error;
/// multi-packet KA is deliberately not approximated by silent truncation.
pub fn query_with_answers(
  name : @model.DnsName,
  rr_type : Int32,
  answers : Array[Record],
) -> Bytes raise WireError {
  guard answers.length() <= 255 else {
    raise Malformed("known answer count exceeds 255")
  }
  let out = qm_query(name, rr_type).to_array()
  out[6] = (answers.length() >> 8).to_byte()
  out[7] = (answers.length() & 255).to_byte()
  for record in answers {
    guard record.rr_class == 1 &&
      record.rr_type == rr_type &&
      record.name.same_name(name) else {
      raise Malformed("known answer does not match question")
    }
    let bytes = payload(record)
    guard bytes.length() <= 65535 else {
      raise Malformed("RDATA exceeds wire length")
    }
    append(out, record.name.to_wire())
    put16(out, record.rr_type)
    put16(out, 1) // cache-flush MUST NOT appear in a query's Known Answers.
    out.push((record.ttl >> 24).to_byte())
    out.push(((record.ttl >> 16) & 255U).to_byte())
    out.push(((record.ttl >> 8) & 255U).to_byte())
    out.push((record.ttl & 255U).to_byte())
    put16(out, bytes.length())
    append(out, bytes)
    guard out.length() <= 9000 else {
      raise Malformed("single-packet known answer limit (9000 octets)")
    }
  }
  Bytes::makei(out.length(), i => out[i])
}

///|
fn known_record(
  name : @model.DnsName,
  rr_type : Int32,
  record : Record,
) -> Bytes raise WireError {
  guard record.rr_class == 1 &&
    record.rr_type == rr_type &&
    record.name.same_name(name) else {
    raise Malformed("known answer does not match question")
  }
  let data = payload(record)
  guard data.length() <= 65535 else {
    raise Malformed("RDATA exceeds wire length")
  }
  let out : Array[Byte] = []
  append(out, record.name.to_wire())
  put16(out, record.rr_type)
  put16(out, 1)
  out.push((record.ttl >> 24).to_byte())
  out.push(((record.ttl >> 16) & 255U).to_byte())
  out.push(((record.ttl >> 8) & 255U).to_byte())
  out.push((record.ttl & 255U).to_byte())
  put16(out, data.length())
  append(out, data)
  Bytes::makei(out.length(), i => out[i])
}

///|
/// RFC 6762 7.2: question in the first packet, answer-only continuations,
/// TC on every packet except the last. Caller sends the returned burst together.
/// At most `max_packets * 256 - 1` answers (16383 by default); byte limits
/// can reduce this capacity. An error never returns a partial burst.
pub fn query_packets(
  name : @model.DnsName,
  rr_type : Int32,
  answers : Array[Record],
  max_size~ : Int32 = 9000,
  max_packets~ : Int32 = 64,
) -> Array[Bytes] raise WireError {
  guard max_size >= 512 &&
    max_size <= 9000 &&
    max_packets > 0 &&
    max_packets <= 64 else {
    raise Malformed("invalid known-answer burst bounds")
  }
  guard answers.length() <= max_packets * 256 - 1 else {
    raise Malformed("known-answer count exceeds packet budget")
  }
  let result : Array[Bytes] = []
  let mut out = qm_query(name, rr_type).to_array()
  let mut count = 0
  let mut capacity = 255
  fn finish(bytes : Array[Byte], records : Int32, more : Bool) -> Bytes {
    bytes[2] = if more { b'\x02' } else { b'\x00' }
    bytes[6] = (records >> 8).to_byte()
    bytes[7] = (records & 255).to_byte()
    Bytes::makei(bytes.length(), i => bytes[i])
  }
  for record in answers {
    let data = known_record(name, rr_type, record)
    if out.length() + data.length() > max_size || count >= capacity {
      guard count > 0 else {
        raise Malformed("one known answer exceeds packet size")
      }
      guard result.length() + 1 < max_packets else {
        raise Malformed("known-answer burst exceeds configured bounds")
      }
      result.push(finish(out, count, true))
      out = Array::make(12, b'\x00')
      count = 0
      capacity = 256
    }
    guard out.length() + data.length() <= max_size else {
      raise Malformed("one known answer exceeds packet size")
    }
    append(out, data)
    count += 1
  }
  result.push(finish(out, count, false))
  result
}
