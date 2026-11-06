///|
pub impl Show for TransportError with fn output(self, logger) {
  match self {
    BrowserClosed => logger.write_string("transport_closed")
    DriverBusy => logger.write_string("browser_driver_busy")
    InvalidArgument(detail) =>
      logger.write_string("invalid_transport_argument: " + detail)
    InterfaceUnavailable =>
      logger.write_string(
        "interface_unavailable: selected interface inactive or changed",
      )
    SocketError(context, code) =>
      logger.write_string("transport_error: \{context} (OS/code \{code})")
  }
}

///|
/// Stable classification; OS-specific context and code remain in SocketError.
pub fn TransportError::diagnostic_code(self : TransportError) -> String {
  match self {
    BrowserClosed => "transport_closed"
    DriverBusy => "browser_driver_busy"
    InvalidArgument(_) => "invalid_transport_argument"
    InterfaceUnavailable => "interface_unavailable"
    SocketError(_, _) => "socket_error"
  }
}

///|
#deprecated
pub extend TransportError with Show::{to_string, output}
