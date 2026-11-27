///|
#derive(Debug)
pub suberror InputError {
  InvalidInput(String)
}

///|
/// DNS labels as immutable octets. Never split an instance label on dots.
#derive(Debug)
pub struct DnsName {
  priv labels : Array[Bytes]
  priv key : Bytes
}

///|
pub fn DnsName::from_labels(labels : Array[Bytes]) -> DnsName raise InputError {
  let mut size = 1
  for label in labels {
    guard label.length() > 0 && label.length() <= 63 else {
      raise InvalidInput("DNS label must contain 1..63 octets")
    }
    size += label.length() + 1
    guard size <= 256 else {
      raise InvalidInput("mDNS name exceeds 255 octets plus terminator")
    }
  }
  let folded : Array[Byte] = []
  for label in labels {
    folded.push(label.length().to_byte())
    for byte in label {
      let value = byte.to_int()
      folded.push(
        (if value >= 65 && value <= 90 { value + 32 } else { value }).to_byte(),
      )
    }
  }
  folded.push(0)
  { labels: labels.copy(), key: Bytes::makei(folded.length(), i => folded[i]), }
}

///|
pub fn DnsName::from_utf8_labels(
  labels : Array[String],
) -> DnsName raise InputError {
  DnsName::from_labels(labels.map(s => @utf8.encode(s)))
}

///|
pub fn DnsName::labels(self : DnsName) -> Array[Bytes] {
  self.labels.copy()
}

///|
pub fn DnsName::to_wire(self : DnsName) -> Bytes {
  let out : Array[Byte] = []
  for label in self.labels {
    out.push(label.length().to_byte())
    for b in label {
      out.push(b)
    }
  }
  out.push(0)
  Bytes::makei(out.length(), i => out[i])
}

///|
/// A collision-free wire key with ASCII case folding only.
pub fn DnsName::canonical_key(self : DnsName) -> Bytes {
  self.key
}

///|
pub fn DnsName::same_name(self : DnsName, other : DnsName) -> Bool {
  self.canonical_key() == other.canonical_key()
}

///|
/// Absolute, reversible ASCII presentation. UTF-8 remains intact in labels().
pub fn DnsName::to_presentation(self : DnsName) -> String {
  let out = StringBuilder()
  for label in self.labels {
    for b in label {
      let n = b.to_int()
      if n >= 33 && n <= 126 && n != 46 && n != 92 {
        out.write_char(n.unsafe_to_char())
      } else {
        out.write_string("\\")
        out.write_char((48 + n / 100).unsafe_to_char())
        out.write_char((48 + n / 10 % 10).unsafe_to_char())
        out.write_char((48 + n % 10).unsafe_to_char())
      }
    }
    out.write_char('.')
  }
  if self.labels.is_empty() {
    "."
  } else {
    out.to_string()
  }
}
