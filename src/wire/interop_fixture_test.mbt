///|
// Self-hosted python-zeroconf 0.148.0 response, recorded 2026-10-23.
// SHA256 ff70b5a3f76802870c90262b338eec5a5d430c4f536c52036733e0737a45f42b.
test "smoke: independent zeroconf packet resolves wire fields including binary TXT" {
  let data : Bytes = b"\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x04\x05\x5f\x68\x74\x74\x70\x04\x5f\x74\x63\x70\x05\x6c\x6f\x63\x61\x6c\x00\x00\x0c\x00\x01\x00\x00\x11\x94\x00\x1c\x19\x6d\x6f\x6f\x6e\x64\x69\x73\x63\x6f\x76\x65\x72\x2d\x35\x30\x65\x63\x36\x64\x63\x66\x36\x37\x33\x32\xc0\x0c\xc0\x28\x00\x10\x80\x01\x00\x00\x11\x94\x00\x30\x1e\x64\x65\x6d\x6f\x3d\x6d\x6f\x6f\x6e\x64\x69\x73\x63\x6f\x76\x65\x72\x2d\x35\x30\x65\x63\x36\x64\x63\x66\x36\x37\x33\x32\x09\x62\x69\x6e\x61\x72\x79\x3d\x00\xff\x06\x65\x6d\x70\x74\x79\x3d\xc0\x28\x00\x21\x80\x01\x00\x00\x00\x78\x00\x22\x00\x00\x00\x00\xa8\xd3\x19\x6d\x6f\x6f\x6e\x64\x69\x73\x63\x6f\x76\x65\x72\x2d\x35\x30\x65\x63\x36\x64\x63\x66\x36\x37\x33\x32\xc0\x17\xc0\x28\x00\x2f\x80\x01\x00\x00\x00\x78\x00\x08\xc0\x28\x00\x04\x00\x00\x00\x08\xc0\x92\x00\x01\x80\x01\x00\x00\x00\x78\x00\x04\x0a\x0c\xb3\x17"
  let message = @wire.decode(data)
  assert_eq(message.flags, 0x8400)
  assert_eq(message.records.length(), 5)
  let mut ptr = false
  let mut srv = false
  let mut txt = false
  let mut address = false
  let mut unknown = false
  for record in message.records {
    match record.data {
      @wire.Ptr(name) => {
        assert_eq(
          name.to_presentation(),
          "moondiscover-50ec6dcf6732._http._tcp.local.",
        )
        assert_false(record.cache_flush)
        ptr = true
      }
      @wire.Srv(priority, weight, port, target) => {
        assert_eq(priority, 0)
        assert_eq(weight, 0)
        assert_eq(port, 43219)
        assert_eq(target.to_presentation(), "moondiscover-50ec6dcf6732.local.")
        srv = true
      }
      @wire.Txt(value) => {
        assert_eq(value.lookup("binary"), @model.Value(b"\x00\xff"))
        assert_eq(value.lookup("empty"), @model.Value(b""))
        txt = true
      }
      @wire.A(value) => {
        assert_eq(value, b"\x0a\x0c\xb3\x17")
        address = true
      }
      @wire.Nsec(_, bitmap) => {
        assert_false(@wire.nsec_contains(bitmap, 33))
        assert_true(@wire.nsec_contains(bitmap, 28))
        unknown = true
      }
      _ => ()
    }
  }
  assert_true(ptr && srv && txt && address && unknown)
}
