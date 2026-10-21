// 📁 lib/screens/address_book_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../api/client.dart';
import '../services/checkout_service.dart';
import '../theme/app_theme.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({Key? key}) : super(key: key);
  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _streetController = TextEditingController();
  final _subCityController = TextEditingController();
  final _woredaController = TextEditingController();
  final _cityController = TextEditingController(text: 'Addis Ababa');
  final _businessController = TextEditingController();
  final _phoneController = TextEditingController();
  final _deliveryNotesController = TextEditingController();

  // Region / Zone / Woreda cascading dropdowns
  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _woredas = [];
  int? _selectedRegionId;
  int? _selectedZoneId;
  int? _selectedWoredaId;

  // Optional coordinates from GPS
  Map<String, dynamic>? _detectedCoords;

  bool _showForm = false;
  bool _saving = false;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
    _loadRegions();
  }

  // ─── Data loading ────────────────────────────────────
  Future<void> _loadAddresses() async {
    try {
      final response = await ApiClient.instance.get('/addresses');
      final List raw = response.data is List ? response.data : response.data['data'] ?? [];
      setState(() {
        _addresses = raw.map((a) => Map<String, dynamic>.from(a)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRegions() async {
    try {
      final res = await ApiClient.instance.get('/regions');
      final List raw = res.data is List ? res.data : res.data['data'] ?? [];
      setState(() => _regions = raw.map((r) => Map<String, dynamic>.from(r)).toList());
    } catch (_) {}
  }

  // These optional nested endpoints may not exist; errors are silently ignored.
  Future<void> _loadZones(int regionId) async {
    setState(() {
      _zones = [];
      _selectedZoneId = null;
      _selectedWoredaId = null;
      _woredas = [];
    });
    try {
      final res = await ApiClient.instance.get('/regions/$regionId/zones');
      final List raw = res.data is List ? res.data : res.data['data'] ?? [];
      setState(() => _zones = raw.map((z) => Map<String, dynamic>.from(z)).toList());
    } catch (_) {}
  }

  Future<void> _loadWoredas(int zoneId) async {
    setState(() {
      _woredas = [];
      _selectedWoredaId = null;
    });
    try {
      final res = await ApiClient.instance.get('/zones/$zoneId/woredas');
      final List raw = res.data is List ? res.data : res.data['data'] ?? [];
      setState(() => _woredas = raw.map((w) => Map<String, dynamic>.from(w)).toList());
    } catch (_) {}
  }

  // ─── GPS auto‑fill (same as checkout) ───────────────
  Future<void> _detectLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Location permission denied');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showError('Location permanently denied');
      return;
    }

    setState(() => _detecting = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      ).timeout(const Duration(seconds: 5));

      final result = await CheckoutService.reverseGeocode(position.latitude, position.longitude);
      final addressLine = result['address'] as String? ?? '';
      final structured = result['structured'] as Map<String, dynamic>? ?? {};

      // Pre‑fill fields
      _streetController.text = structured['street'] as String? ?? '';
      _subCityController.text = structured['sub_city'] as String? ?? '';
      _woredaController.text = structured['woreda'] as String? ?? '';
      _cityController.text = structured['city'] as String? ?? 'Addis Ababa';

      final businessMatch = RegExp(r'\(near (.+?)\)').firstMatch(addressLine);
      _businessController.text = businessMatch?.group(1) ?? '';

      _selectedRegionId = structured['region_id'] as int? ?? 14;
      _selectedZoneId = structured['zone_id'] as int?;
      _selectedWoredaId = structured['woreda_id'] as int?;

      // Store coordinates for saving
      _detectedCoords = {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };

      // Load cascading lists to match selected IDs (optional)
      if (_selectedRegionId != null) await _loadZones(_selectedRegionId!);
      if (_selectedZoneId != null) await _loadWoredas(_selectedZoneId!);

      setState(() {
        _showForm = true;
        _detecting = false;
      });
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
    } catch (e) {
      setState(() => _detecting = false);
      _showError('Could not detect location: ${e.toString().substring(0, 80)}');
    }
  }

  // ─── Save new / updated address ──────────────────────
  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRegionId == null) {
      _showError('Please select a region');
      return;
    }

    // Build address_line like checkout
    final parts = [
      _streetController.text.trim(),
      _subCityController.text.trim(),
      _woredaController.text.trim(),
      _cityController.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    String addrLine = parts.join(', ');
    if (_businessController.text.trim().isNotEmpty) {
      addrLine += ' (near ${_businessController.text.trim()})';
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'address': {
          'address_line': addrLine,
          'region_id': _selectedRegionId,
          'zone_id': _selectedZoneId,
          'woreda_id': _selectedWoredaId,
          'phone': _phoneController.text.trim(),
          'delivery_notes': _deliveryNotesController.text.trim(),
          'is_default': _addresses.isEmpty, // first address becomes default
          // Additional structured fields
          'sub_city': _subCityController.text.trim().isNotEmpty ? _subCityController.text.trim() : null,
          'city': _cityController.text.trim().isNotEmpty ? _cityController.text.trim() : null,
          'woreda_text': _woredaController.text.trim().isNotEmpty ? _woredaController.text.trim() : null,
          'street': _streetController.text.trim().isNotEmpty ? _streetController.text.trim() : null,
          'landmark': _businessController.text.trim().isNotEmpty ? _businessController.text.trim() : null,
          // Source: auto if we detected coords, manual otherwise
          'source': _detectedCoords != null ? 'auto' : 'manual',
          // Include coordinates if available
          'latitude': _detectedCoords?['latitude'],
          'longitude': _detectedCoords?['longitude'],
        }
      };
      await ApiClient.instance.post('/addresses', data: payload);
      _clearForm();
      _loadAddresses();
    } catch (e) {
      _showError('Failed to save address');
    } finally {
      setState(() => _saving = false);
    }
  }

  // ─── Delete ──────────────────────────────────────────
  Future<void> _deleteAddress(int id) async {
    try {
      await ApiClient.instance.delete('/addresses/$id');
      _loadAddresses();
    } catch (e) {
      _showError('Failed to delete address');
    }
  }

  void _clearForm() {
    _streetController.clear();
    _subCityController.clear();
    _woredaController.clear();
    _cityController.text = 'Addis Ababa';
    _businessController.clear();
    _phoneController.clear();
    _deliveryNotesController.clear();
    setState(() {
      _selectedRegionId = null;
      _selectedZoneId = null;
      _selectedWoredaId = null;
      _zones = [];
      _woredas = [];
      _detectedCoords = null;
      _showForm = false;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _streetController.dispose();
    _subCityController.dispose();
    _woredaController.dispose();
    _cityController.dispose();
    _businessController.dispose();
    _phoneController.dispose();
    _deliveryNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text('Address Book', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAddresses,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Existing addresses
                  ..._addresses.map((addr) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.location_on, color: AppColors.primary),
                          ),
                          title: Text(addr['address_line'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (addr['phone'] != null) Text(addr['phone']),
                              if (addr['delivery_notes'] != null && addr['delivery_notes'].toString().isNotEmpty)
                                Text('📝 ${addr['delivery_notes']}', style: TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _deleteAddress(addr['id']),
                          ),
                        ),
                      )),

                  // GPS detection button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _detecting ? null : _detectLocation,
                      icon: _detecting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: Text(_detecting ? 'Detecting…' : 'Use current location'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.textPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Toggle add form
                  if (!_showForm)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _showForm = true),
                        icon: const Icon(Icons.add),
                        label: const Text('Add New Address'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),

                  if (_showForm) ...[
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('New Address', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),

                              // Region
                              DropdownButtonFormField<int>(
                                value: _selectedRegionId,
                                decoration: _inputDecoration('Region *'),
                                items: _regions.map((r) => DropdownMenuItem<int>(value: r['id'], child: Text(r['name']))).toList(),
                                onChanged: (v) {
                                  setState(() => _selectedRegionId = v);
                                  if (v != null) _loadZones(v);
                                },
                                validator: (v) => v == null ? 'Select region' : null,
                              ),
                              const SizedBox(height: 12),

                              // Zone (if available)
                              if (_zones.isNotEmpty)
                                DropdownButtonFormField<int>(
                                  value: _selectedZoneId,
                                  decoration: _inputDecoration('Zone'),
                                  items: _zones.map((z) => DropdownMenuItem<int>(value: z['id'], child: Text(z['name']))).toList(),
                                  onChanged: (v) {
                                    setState(() => _selectedZoneId = v);
                                    if (v != null) _loadWoredas(v);
                                  },
                                ),
                              if (_zones.isNotEmpty) const SizedBox(height: 12),

                              // Woreda (if available)
                              if (_woredas.isNotEmpty)
                                DropdownButtonFormField<int>(
                                  value: _selectedWoredaId,
                                  decoration: _inputDecoration('Woreda'),
                                  items: _woredas.map((w) => DropdownMenuItem<int>(value: w['id'], child: Text(w['name']))).toList(),
                                  onChanged: (v) => setState(() => _selectedWoredaId = v),
                                ),
                              if (_woredas.isNotEmpty) const SizedBox(height: 12),

                              // Street
                              TextFormField(
                                controller: _streetController,
                                decoration: _inputDecoration('Street / Address Line *'),
                                validator: (v) => v?.isEmpty == true ? 'Enter street' : null,
                              ),
                              const SizedBox(height: 12),

                              // Sub‑City
                              TextFormField(
                                controller: _subCityController,
                                decoration: _inputDecoration('Sub‑City / Area'),
                              ),
                              const SizedBox(height: 12),

                              // Woreda name (optional, additional to dropdown)
                              TextFormField(
                                controller: _woredaController,
                                decoration: _inputDecoration('Woreda (name)'),
                              ),
                              const SizedBox(height: 12),

                              // City
                              TextFormField(
                                controller: _cityController,
                                decoration: _inputDecoration('City *'),
                                validator: (v) => v?.isEmpty == true ? 'Enter city' : null,
                              ),
                              const SizedBox(height: 12),

                              // Business / Landmark
                              TextFormField(
                                controller: _businessController,
                                decoration: _inputDecoration('Nearby Business / Landmark'),
                              ),
                              const SizedBox(height: 12),

                              // Phone
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: _inputDecoration('Phone *'),
                                validator: (v) => v?.isEmpty == true ? 'Enter phone' : null,
                              ),
                              const SizedBox(height: 12),

                              // Delivery notes
                              TextFormField(
                                controller: _deliveryNotesController,
                                maxLines: 2,
                                decoration: _inputDecoration('Delivery Notes (optional)'),
                              ),
                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _saving ? null : _saveAddress,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: _saving
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _clearForm,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.textPrimary,
                                        side: const BorderSide(color: AppColors.textPrimary),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}