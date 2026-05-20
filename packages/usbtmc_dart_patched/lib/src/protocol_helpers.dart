import 'dart:typed_data';
import 'constants.dart';

class UsbtmcProtocolHelpers {
  /// Increments tag to keep it between 1 and 255.
  static int nextbTag(int currentTag) {
    return (currentTag % 255) + 1;
  }

  /// Calculates one's complement of the tag.
  static int invertbTag(int tag) {
    return (~tag) & 0xFF;
  }

  /// Generates the first 4 bytes of the USBTMC message Bulk-OUT Header prefix.
  static Uint8List encodeBulkHeaderPrefix(int tag, int msgId) {
    final prefix = Uint8List(4);
    prefix[0] = msgId;
    prefix[1] = tag;
    prefix[2] = invertbTag(tag);
    prefix[3] = 0x00; // Reserved
    return prefix;
  }

  /// Encodes devDepMsgOut Bulk-OUT Header (12 bytes).
  static Uint8List encodeBulkOutHeader(int tag, int transferSize, bool eom) {
    final header = Uint8List(12);
    final prefix = encodeBulkHeaderPrefix(tag, UsbtmcConstants.devDepMsgOut);
    
    // Bytes 0-3: Prefix
    header.setRange(0, 4, prefix);

    // Bytes 4-7: TransferSize (32-bit little-endian)
    final byteData = ByteData.sublistView(header, 4, 8);
    byteData.setUint32(0, transferSize, Endian.little);

    // Byte 8: bmTransferAttributes (bit 0 = EOM)
    header[8] = eom ? 0x01 : 0x00;

    // Bytes 9-11: Reserved (all 0x00)
    header[9] = 0x00;
    header[10] = 0x00;
    header[11] = 0x00;

    return header;
  }

  /// Encodes requestDevDepMsgIn Bulk-OUT Header (12 bytes).
  static Uint8List encodeMsgInBulkOutHeader(
    int tag,
    int transferSize,
    bool termCharEnabled,
    int termChar,
  ) {
    final header = Uint8List(12);
    final prefix = encodeBulkHeaderPrefix(tag, UsbtmcConstants.requestDevDepMsgIn);

    // Bytes 0-3: Prefix
    header.setRange(0, 4, prefix);

    // Bytes 4-7: TransferSize (32-bit little-endian)
    final byteData = ByteData.sublistView(header, 4, 8);
    byteData.setUint32(0, transferSize, Endian.little);

    // Byte 8: bmTransferAttributes (bit 1 = termCharEnabled)
    header[8] = termCharEnabled ? 0x02 : 0x00;

    // Byte 9: TermChar
    header[9] = termChar;

    // Bytes 10-11: Reserved (all 0x00)
    header[10] = 0x00;
    header[11] = 0x00;

    return header;
  }

  /// Computes padding length so the total USBTMC transfer (header + payload)
  /// is a multiple of 4 bytes, as required by the USBTMC spec.
  ///
  /// [totalTransferLength] must be the sum of the 12-byte header and the
  /// payload length.
  static int getPaddingLength(int totalTransferLength) {
    final moduloFour = totalTransferLength % 4;
    return moduloFour == 0 ? 0 : 4 - moduloFour;
  }
}
