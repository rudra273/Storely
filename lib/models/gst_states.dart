/// GST state codes (first two digits of a GSTIN) and their names, as used
/// for "Place of Supply" on invoices.
const gstStateNames = <String, String>{
  '01': 'Jammu and Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '25': 'Daman and Diu',
  '26': 'Dadra and Nagar Haveli and Daman and Diu',
  '27': 'Maharashtra',
  '28': 'Andhra Pradesh (Old)',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
  '97': 'Other Territory',
  '99': 'Centre Jurisdiction',
};

/// The 2-digit state code in [value] (a code or a GSTIN), or null.
String? gstStateCode(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.length < 2) return null;
  final code = trimmed.substring(0, 2);
  return RegExp(r'^\d{2}$').hasMatch(code) ? code : null;
}

/// "27 - Maharashtra" (or just the code when it is unknown).
String gstStateLabel(String code) {
  final name = gstStateNames[code];
  return name == null ? code : '$code - $name';
}
