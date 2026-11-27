///|
#derive(Eq, Debug)
pub(all) enum TxtValue {
  Missing
  Flag
  Value(Bytes)
}

///|
#derive(Debug)
pub struct TxtRecord {
  priv entries : Array[Bytes]
}

///|
pub fn TxtRecord::from_entries(
  entries : Array[Bytes],
) -> TxtRecord raise InputError {
  let mut size = 0
  for entry in entries {
    guard entry.length() <= 255 else {
      raise InvalidInput("TXT entry exceeds 255 octets")
    }
    size += 1 + entry.length()
    guard size <= 65535 else {
      raise InvalidInput("TXT RDATA exceeds 65535 octets")
    }
  }
  { entries: entries.copy(), }
}

///|
pub fn TxtRecord::from_wire(data : Bytes) -> TxtRecord raise InputError {
  guard data.length() <= 65535 else {
    raise InvalidInput("TXT RDATA exceeds 65535 octets")
  }
  let entries : Array[Bytes] = []
  let mut offset = 0
  while offset < data.length() {
    let size = data[offset].to_int()
    offset += 1
    guard size <= data.length() - offset else {
      raise InvalidInput("truncated TXT entry")
    }
    entries.push(data[offset:offset + size].to_owned())
    offset += size
  }
  TxtRecord::from_entries(entries)
}

///|
pub fn TxtRecord::entries(self : TxtRecord) -> Array[Bytes] {
  self.entries.copy()
}

///|
pub fn TxtRecord::to_wire(self : TxtRecord) -> Bytes {
  let out : Array[Byte] = []
  for entry in self.entries {
    out.push(entry.length().to_byte())
    for b in entry {
      out.push(b)
    }
  }
  Bytes::makei(out.length(), i => out[i])
}

///|
fn folded(b : Byte) -> Byte {
  let n = b.to_int()
  (if n >= 65 && n <= 90 { n + 32 } else { n }).to_byte()
}

///|
/// First matching key wins (RFC 6763 section 6.4). Values stay binary.
/// Invalid/empty keys are preserved in entries(), ignored during lookup.
pub fn TxtRecord::lookup(
  self : TxtRecord,
  key : String,
) -> TxtValue raise InputError {
  let wanted = @utf8.encode(key)
  guard wanted.length() > 0 else { raise InvalidInput("empty TXT key") }
  for b in wanted {
    let n = b.to_int()
    guard n >= 32 && n <= 126 && n != 61 else {
      raise InvalidInput("TXT key must be printable ASCII without '='")
    }
  }
  for entry in self.entries {
    let mut end = 0
    let mut valid = true
    while end < entry.length() && entry[end] != b'=' {
      let n = entry[end].to_int()
      if n < 32 || n > 126 {
        valid = false
      }
      end += 1
    }
    if valid && end == wanted.length() {
      let mut equal = true
      for i in 0..<end {
        if folded(entry[i]) != folded(wanted[i]) {
          equal = false
        }
      }
      if equal {
        return if end == entry.length() {
          Flag
        } else {
          Value(entry[end + 1:].to_owned())
        }
      }
    }
  }
  Missing
}
