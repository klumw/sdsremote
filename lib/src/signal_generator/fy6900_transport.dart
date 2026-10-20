/// Transport seam for the FeelElec FY6900.
///
/// The FY6900 uses the same line-oriented transaction contract as the
/// JDS6600, so the shared [Jds6600Transport] interface is reused under a
/// device-specific name. The concrete FY6900 transport differs only in that
/// it delivers the bare-LF acknowledgement as an empty line.
library;

import 'jds6600_transport.dart';

typedef Fy6900Transport = Jds6600Transport;
