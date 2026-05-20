class VisaResource {
  final String resourceString;
  final String interfaceType;
  final int boardIndex;
  final int manufacturerId;
  final int modelCode;
  final String serialNumber;
  final int interfaceIndex;
  final String resourceClass;

  VisaResource({
    required this.resourceString,
    required this.interfaceType,
    required this.boardIndex,
    required this.manufacturerId,
    required this.modelCode,
    required this.serialNumber,
    required this.interfaceIndex,
    required this.resourceClass,
  });

  static final RegExp _visaRegExp = RegExp(
    r'^([A-Za-z]+)(\d*)::' // interfaceType & boardIndex
    r'([^\s:]+)::'         // manufacturerID
    r'([^\s:]+)'           // modelCode
    r'(?:::([^\s:]+))?'    // serialNumber (optional)
    r'(?:::([^\s:]+))?'    // interfaceNumber (optional)
    r'::([^\s:]+)$',       // resourceClass
  );

  static VisaResource parse(String resourceString) {
    final match = _visaRegExp.firstMatch(resourceString);
    if (match == null) {
      throw FormatException('visa: resource string did not match expected format');
    }

    final interfaceType = match.group(1)!.toUpperCase();
    if (interfaceType != 'USB') {
      throw FormatException('visa: interface type was not usb');
    }

    final boardIndexStr = match.group(2);
    final boardIndex = boardIndexStr != null && boardIndexStr.isNotEmpty
        ? int.parse(boardIndexStr)
        : 0;

    final manufacturerIdStr = match.group(3)!;
    final manufacturerId = _parseInt(manufacturerIdStr);

    final modelCodeStr = match.group(4)!;
    final modelCode = _parseInt(modelCodeStr);

    final serialNumber = match.group(5) ?? '';

    final interfaceIndexStr = match.group(6);
    final interfaceIndex = interfaceIndexStr != null && interfaceIndexStr.isNotEmpty
        ? int.parse(interfaceIndexStr)
        : 0;

    final resourceClass = match.group(7)!.toUpperCase();
    if (resourceClass != 'INSTR') {
      throw FormatException('visa: resource class was not instr');
    }

    return VisaResource(
      resourceString: resourceString,
      interfaceType: 'USB',
      boardIndex: boardIndex,
      manufacturerId: manufacturerId,
      modelCode: modelCode,
      serialNumber: serialNumber,
      interfaceIndex: interfaceIndex,
      resourceClass: 'INSTR',
    );
  }

  static int _parseInt(String value) {
    if (value.toLowerCase().startsWith('0x')) {
      return int.parse(value.substring(2), radix: 16);
    }
    return int.parse(value);
  }

  @override
  String toString() {
    return 'VisaResource(interfaceType: $interfaceType, boardIndex: $boardIndex, '
        'manufacturerId: 0x${manufacturerId.toRadixString(16).toUpperCase()}, '
        'modelCode: 0x${modelCode.toRadixString(16).toUpperCase()}, '
        'serialNumber: $serialNumber, interfaceIndex: $interfaceIndex, '
        'resourceClass: $resourceClass)';
  }
}
