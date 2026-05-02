import 'dart:typed_data';

/// Stateless parser for SCPI responses from Siglent SDS oscilloscopes.
class ScpiParser {
  /// Parses an IEEE-488.2 binary block with header `#<n><len><data>`.
  ///
  /// Returns the pure payload bytes (without header, without trailing 0x0A).
  /// Throws [FormatException] if the header is missing or malformed.
  static Uint8List parseDataBlock(Uint8List raw) {
    // The instrument may prefix the block with a command echo such as
    // "C1:WF DAT2," before the '#' marker. Scan forward to find '#'.
    int offset = 0;
    while (offset < raw.length && raw[offset] != 0x23 /* '#' */) {
      offset++;
    }

    if (offset >= raw.length) {
      throw FormatException(
        'Invalid IEEE-488.2 block: missing # marker',
        raw,
      );
    }

    // Work on the sub-view starting at '#'
    final raw2 = Uint8List.sublistView(raw, offset);

    if (raw2.length < 2) {
      throw FormatException(
        'Invalid IEEE-488.2 block: too short to contain n digit',
        raw,
      );
    }

    // Siglent non-standard variant: #! followed by 4-byte big-endian length
    int dataStart;
    int dataLen;
    if (raw2[1] == 0x21 /* '!' */) {
      if (raw2.length < 6) {
        throw FormatException(
          'Invalid IEEE-488.2 block: too short for #! header',
          raw,
        );
      }
      dataLen = (raw2[2] << 24) | (raw2[3] << 16) | (raw2[4] << 8) | raw2[5];
      dataStart = 6;
    } else {
      final nDigit = raw2[1] - 0x30; // ASCII '0' = 0x30
      if (nDigit < 1 || nDigit > 9) {
        throw FormatException(
          'Invalid IEEE-488.2 block: n digit out of range (got $nDigit)',
          raw,
        );
      }

      // Header is: '#' + n_char + n_chars_of_length = 2 + nDigit bytes
      final headerLen = 2 + nDigit;
      if (raw2.length < headerLen) {
        throw FormatException(
          'Invalid IEEE-488.2 block: too short to contain length field',
          raw,
        );
      }

      // Parse the length digits as ASCII
      dataLen = 0;
      for (int i = 2; i < headerLen; i++) {
        final digit = raw2[i] - 0x30;
        if (digit < 0 || digit > 9) {
          throw FormatException(
            'Invalid IEEE-488.2 block: non-digit in length field',
            raw,
          );
        }
        dataLen = dataLen * 10 + digit;
      }
      dataStart = headerLen;
    }

    final dataEnd = dataStart + dataLen;

    if (dataEnd > raw2.length) {
      throw FormatException(
        'Invalid IEEE-488.2 block: declared length $dataLen exceeds available bytes',
        raw,
      );
    }

    // The payload is exactly the declared bytes.
    // A trailing 0x0A terminator may appear after the payload in the raw buffer
    // but is not part of the returned data.
    return Uint8List.sublistView(raw2, dataStart, dataEnd);
  }

  static const Map<String, double> _siPrefixes = {
    'G': 1e9,
    'M': 1e6,
    'k': 1e3,
    'm': 1e-3,
    'u': 1e-6,
    'n': 1e-9,
  };

  /// Parses a SCPI value string such as `"5.00E-01V"`, `"1.00GSa/s"`, `"2.50E-02"`.
  ///
  /// Handles SI prefixes (G, M, k, m, u, n) and ignores unit suffixes.
  /// Throws [FormatException] if the string does not contain a valid number.
  static double parseValue(String raw) {
    var s = raw.trim();
    if (s.isEmpty) {
      throw FormatException('Invalid SCPI value: empty string', raw);
    }

    // Siglent instruments echo the command name before the value, e.g.
    // "TDIV 5.00E-05S" or "C1:VDIV 2.00E-01V". Strip everything up to and
    // including the last space so we are left with just the value string.
    final lastSpace = s.lastIndexOf(' ');
    if (lastSpace >= 0) s = s.substring(lastSpace + 1).trim();

    // Try plain double / scientific notation first (no SI prefix)
    final plainValue = double.tryParse(s);
    if (plainValue != null) return plainValue;

    // Walk through the string to find the numeric part.
    // A valid number may start with an optional '-' or '+', then digits,
    // optional '.', more digits, optional exponent 'E'/'e' with sign and digits.
    final numRegex = RegExp(
      r'^([+-]?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?)',
    );
    final match = numRegex.firstMatch(s);
    if (match == null) {
      throw FormatException('Invalid SCPI value: no numeric part found', raw);
    }

    final numStr = match.group(1)!;
    final numValue = double.tryParse(numStr);
    if (numValue == null) {
      throw FormatException('Invalid SCPI value: cannot parse number', raw);
    }

    // The character immediately after the numeric part may be an SI prefix
    final rest = s.substring(numStr.length);
    if (rest.isEmpty) return numValue;

    final firstChar = rest[0];
    final factor = _siPrefixes[firstChar];
    if (factor != null) {
      return numValue * factor;
    }

    // No SI prefix — the rest is a unit suffix, ignore it
    return numValue;
  }

  /// Parses a SCPI status string such as `"C1:TRA ON"`, `"C1:TRA OFF"`, `"1"`, `"0"`.
  ///
  /// Returns `true` for ON/1 and `false` for OFF/0.
  static bool parseStatus(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.isEmpty) return false;

    // Strip command echo if present
    final lastSpace = s.lastIndexOf(' ');
    if (lastSpace >= 0) s = s.substring(lastSpace + 1).trim();

    return s == 'ON' || s == '1';
  }

  /// Formats a [double] value as a SCPI-compatible string.
  ///
  /// Uses scientific notation with enough precision for a round-trip via
  /// [parseValue].
  static String formatValue(double value) {
    // toStringAsExponential(17) gives enough digits for a lossless round-trip
    // of any IEEE-754 double. The result is plain scientific notation that
    // parseValue can handle directly (no SI prefix, no unit suffix).
    return value.toStringAsExponential(17);
  }
}
