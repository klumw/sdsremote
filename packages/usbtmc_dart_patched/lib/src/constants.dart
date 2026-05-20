// Constants for USBTMC (USB Test and Measurement Class) and USB488 subclass.

class UsbtmcConstants {
  static const int ioBufferSize = 1024 * 1024; // 1 MB
  static const int headerSize = 12;
  static const int maxPacketSize = 512;

  // bInterfaceClass
  static const int applicationSpecificBaseClass = 0xfe;

  // bInterfaceSubClass
  static const int usbtmcSubClass = 0x03;

  // bInterfaceProtocol
  static const int usbtmcProtocol = 0x00;
  static const int usb488Protocol = 0x01;

  // MsgID values
  static const int devDepMsgOut = 1;
  static const int requestDevDepMsgIn = 2;
  static const int devDepMsgIn = 2;
  static const int vendorSpecificOut = 126;
  static const int requestVendorSpecificIn = 127;
  static const int vendorSpecificIn = 127;
  static const int trigger = 128;

  // bRequest values (USBTMC)
  static const int initiateAbortBulkOut = 1;
  static const int checkAbortBulkOutStatus = 2;
  static const int initiateAbortBulkIn = 3;
  static const int checkAbortBulkInStatus = 4;
  static const int initiateClear = 5;
  static const int checkClearStatus = 6;
  static const int getCapabilities = 7;
  static const int indicatorPulse = 64;

  // bRequest values (USB488)
  static const int readStatusByte = 128;
  static const int renControl = 160;
  static const int goToLocal = 161;
  static const int localLockout = 162;

  // Status values
  static const int statusSuccess = 0x01;
  static const int statusPending = 0x02;
  static const int statusInterruptInBusy = 0x20;
  static const int statusFailed = 0x80;
  static const int statusTransferNotInProgress = 0x81;
  static const int statusSplitNotInProgress = 0x82;
  static const int statusSplitInProgress = 0x83;

  // Descriptions for bRequest
  static const Map<int, String> requestDescriptions = {
    initiateAbortBulkOut: 'Aborts a Bulk-OUT transfer.',
    checkAbortBulkOutStatus: 'Returns the status of the previously sent initiateAbortBulkOut request.',
    initiateAbortBulkIn: 'Aborts a Bulk-IN transfer.',
    checkAbortBulkInStatus: 'Returns the status of the previously sent initiateAbortBulkIn request.',
    initiateClear: 'Clears all previously sent pending and unprocessed Bulk-OUT USBTMC message content and clears all pending Bulk-IN transfers from the USBTMC interface.',
    checkClearStatus: 'Returns the status of the previously sent initiateClear request.',
    getCapabilities: 'Returns attributes and capabilities of the USBTMC interface.',
    indicatorPulse: 'A mechanism to turn on an activity indicator for identification purposes.',
    readStatusByte: 'Returns the IEEE 488 Status Byte.',
    renControl: 'Mechanism to enable or disable local controls on a device.',
    goToLocal: 'Mechanism to enable local controls on a device.',
    localLockout: 'Mechanism to disable local controls on a device.',
  };

  static String getRequestDescription(int request) {
    return requestDescriptions[request] ?? 'Unknown USBTMC/USB488 request';
  }
}
