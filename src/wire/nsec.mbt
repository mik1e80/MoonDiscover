///|
/// Query a restricted window-zero bitmap. Types outside this window are not
/// reported as present; callers must separately constrain negative inference.
pub fn nsec_contains(bitmap : Bytes, rr_type : Int32) -> Bool {
  rr_type >= 0 &&
  rr_type <= 255 &&
  rr_type / 8 < bitmap.length() &&
  (bitmap[rr_type / 8].to_int() & (128 >> (rr_type % 8))) != 0
}
