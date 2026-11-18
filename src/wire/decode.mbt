///|
pub suberror WireError {
  Malformed(String)
}

///|
pub(all) enum RData {
  A(Bytes)
  Aaaa(Bytes)
  Ptr(@model.DnsName)
  Srv(Int32, Int32, Int32, @model.DnsName)
  Txt(@model.TxtRecord)
  Nsec(@model.DnsName, Bytes)
  Unknown(Bytes)
}

///|
pub(all) enum Section {
  Answer
  Authority
  Additional
}

///|
pub(all) struct Question {
  name : @model.DnsName
  rr_type : Int32
  rr_class : Int32
  unicast_response : Bool
}

///|
pub(all) struct Record {
  name : @model.DnsName
  rr_type : Int32
  rr_class : Int32
  cache_flush : Bool
  ttl : UInt32
  data : RData
  section : Section
}

///|
pub(all) struct Message {
  id : Int32
  flags : Int32
  questions : Array[Question]
  records : Array[Record]
}

///|
fn u16(data : Bytes, at : Int32) -> Int32 {
  (data[at].to_int() << 8) | data[at + 1].to_int()
}

///|
fn u32(data : Bytes, at : Int32) -> UInt32 {
  ((u16(data, at) << 16) | u16(data, at + 2)).reinterpret_as_uint()
}

///|
/// Decode a compressed name; cap dereferences and enforce octet limits.
pub fn decode_name(
  data : Bytes,
  start : Int32,
) -> (@model.DnsName, Int32) raise WireError {
  guard data.length() <= 9000 && start >= 0 && start < data.length() else {
    raise Malformed("name offset/packet length out of bounds")
  }
  let labels : Array[Bytes] = []
  let visited : Array[Int32] = []
  let mut at = start
  let mut next = -1
  let mut size = 1
  for _ in 0..<256 {
    guard at < data.length() else { raise Malformed("truncated name") }
    guard !visited.contains(at) else {
      raise Malformed("compression pointer cycle")
    }
    visited.push(at)
    let length = data[at].to_int()
    if length == 0 {
      let name = @model.DnsName::from_labels(labels) catch {
        _ => raise Malformed("invalid decoded name")
      }
      return (name, if next < 0 { at + 1 } else { next })
    }
    if (length & 0xc0) == 0xc0 {
      guard at + 1 < data.length() else {
        raise Malformed("truncated compression pointer")
      }
      let target = ((length & 0x3f) << 8) | data[at + 1].to_int()
      guard target < at else {
        raise Malformed("compression pointer must refer backwards")
      }
      if next < 0 {
        next = at + 2
      }
      at = target
    } else {
      guard length <= 63 else { raise Malformed("unsupported label encoding") }
      guard length < data.length() - at else {
        raise Malformed("truncated label")
      }
      size += length + 1
      guard size <= 256 else {
        raise Malformed("expanded mDNS name exceeds 255 octets plus terminator")
      }
      labels.push(data[at + 1:at + 1 + length].to_owned())
      at += length + 1
    }
  }
  raise Malformed("name decode step limit (256)")
}

///|
fn rdata(
  data : Bytes,
  rr_type : Int32,
  at : Int32,
  end : Int32,
) -> RData raise WireError {
  match rr_type {
    1 => {
      guard end - at == 4 else { raise Malformed("A must contain 4 octets") }
      A(data[at:end].to_owned())
    }
    28 => {
      guard end - at == 16 else {
        raise Malformed("AAAA must contain 16 octets")
      }
      Aaaa(data[at:end].to_owned())
    }
    12 => {
      let (name, next) = decode_name(data, at)
      guard next == end else { raise Malformed("PTR RDLENGTH mismatch") }
      Ptr(name)
    }
    33 => {
      guard end - at >= 7 else { raise Malformed("SRV too short") }
      let (target, next) = decode_name(data, at + 6)
      guard next == end else { raise Malformed("SRV RDLENGTH mismatch") }
      Srv(u16(data, at), u16(data, at + 2), u16(data, at + 4), target)
    }
    16 => {
      let txt = @model.TxtRecord::from_wire(data[at:end].to_owned()) catch {
        _ => raise Malformed("malformed TXT RDATA")
      }
      Txt(txt)
    }
    47 =>
      // Unsupported NSEC RDATA must not invalidate the other response RRs.
      try {
        let (name, next) = decode_name(data, at)
        guard next + 2 <= end else { raise Malformed("short NSEC bitmap") }
        let length = data[next + 1].to_int()
        guard data[next] == 0 &&
          length >= 1 &&
          length <= 32 &&
          next + 2 + length == end else {
          raise Malformed("unsupported NSEC bitmap")
        }
        let bitmap = data[next + 2:end].to_owned()
        guard !nsec_contains(bitmap, 47) else {
          raise Malformed("NSEC self bit")
        }
        Nsec(name, bitmap)
      } catch {
        _ => Unknown(data[at:end].to_owned())
      }
    _ => Unknown(data[at:end].to_owned())
  }
}

///|
/// Limited DNS-SD decoder. Unknown RR stays opaque; no cache acceptance implied.
pub fn decode(data : Bytes) -> Message raise WireError {
  guard data.length() >= 12 && data.length() <= 9000 else {
    raise Malformed("packet length outside 12..9000")
  }
  let qd = u16(data, 4)
  let an = u16(data, 6)
  let ns = u16(data, 8)
  let ar = u16(data, 10)
  guard qd + an + ns + ar <= 256 else {
    raise Malformed("question/record limit (256)")
  }
  let questions : Array[Question] = []
  let records : Array[Record] = []
  let mut at = 12
  for _ in 0..<qd {
    let (name, next) = decode_name(data, at)
    at = next
    guard data.length() - at >= 4 else { raise Malformed("truncated question") }
    let raw_class = u16(data, at + 2)
    questions.push({
      name,
      rr_type: u16(data, at),
      rr_class: raw_class & 0x7fff,
      unicast_response: (raw_class & 0x8000) != 0,
    })
    at += 4
  }
  for i in 0..<(an + ns + ar) {
    let (name, next) = decode_name(data, at)
    at = next
    guard data.length() - at >= 10 else {
      raise Malformed("truncated RR header")
    }
    let rr_type = u16(data, at)
    let raw_class = u16(data, at + 2)
    let ttl = u32(data, at + 4)
    let length = u16(data, at + 8)
    at += 10
    guard length <= data.length() - at else {
      raise Malformed("truncated RDATA")
    }
    let payload = rdata(data, rr_type, at, at + length)
    records.push({
      name,
      rr_type,
      rr_class: raw_class & 0x7fff,
      cache_flush: (raw_class & 0x8000) != 0,
      ttl,
      data: payload,
      section: if i < an {
        Answer
      } else if i < an + ns {
        Authority
      } else {
        Additional
      },
    })
    at += length
  }
  guard at == data.length() else { raise Malformed("trailing packet octets") }
  { id: u16(data, 0), flags: u16(data, 2), questions, records, }
}

///|
pub fn qm_query(
  name : @model.DnsName,
  rr_type : Int32,
) -> Bytes raise WireError {
  guard rr_type > 0 && rr_type <= 65535 else {
    raise Malformed("question type outside 1..65535")
  }
  let bytes = [
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00',
  ]
  for b in name.to_wire() {
    bytes.push(b)
  }
  bytes.push((rr_type >> 8).to_byte())
  bytes.push((rr_type & 255).to_byte())
  bytes.push(0)
  bytes.push(1)
  Bytes::makei(bytes.length(), i => bytes[i])
}
