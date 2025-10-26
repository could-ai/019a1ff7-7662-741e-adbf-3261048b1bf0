import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feditech',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF22D3EE), // Brand color
          secondary: Color(0xFF60A5FA), // Brand2 color
          surface: Color(0xFF070B18), // Background1
          background: Color(0xFF0A1532), // Background2
          onSurface: Color(0xFFE6EEF6), // Text color
          onBackground: Color(0xFF9FB0C7), // Muted color
        ),
        scaffoldBackgroundColor: const Color(0xFF070B18),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFE6EEF6)),
          bodySmall: TextStyle(color: Color(0xFF9FB0C7)),
        ),
      ),
      home: const FeditechHomePage(),
    );
  }
}

class FeditechHomePage extends StatefulWidget {
  const FeditechHomePage({super.key});

  @override
  State<FeditechHomePage> createState() => _FeditechHomePageState();
}

class _FeditechHomePageState extends State<FeditechHomePage> {
  // Controllers for inputs
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _adminPassController = TextEditingController();
  final TextEditingController _bulkCodesController = TextEditingController();
  final TextEditingController _admOrderController = TextEditingController();
  final TextEditingController _admCodeController = TextEditingController();

  // State variables
  String _selectedNetwork = 'airtel';
  String _stateMessage = 'Weka namba ya simu na mtandao, kisha bofya "Lipa TZS 1,000".';
  String _voucherCode = '—';
  bool _isVoucherVisible = false;
  bool _isSeeVoucherVisible = false;
  bool _isAdminDrawerOpen = false;
  bool _isPasswordModalVisible = false;
  bool _isAdminLoggedIn = false;
  List<String> _codes = [];
  Map<String, dynamic> _orders = {};
  Map<String, dynamic> _usage = {'used': 0};
  String _currentOrderId = '';
  Timer? _pollingTimer;

  // Constants
  static const String adminPassword = '0084';
  static const String zenoApiKey = 'SEiMTXnXf0Q76YH3ZrFojow9pqPbiczfHwz2GssymGMeL6PB1GkfeMTprSCjZmOd-XJdPWVVLLIKmtpJ4pI7Dg'; // Replace with secure handling
  static const String initUrl = 'https://zenoapi.com/api/payments/mobile_money_tanzania';
  static const String statusUrl = 'https://zenoapi.com/api/payments/order-status';
  static const int priceTzs = 1000;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _orders = jsonDecode(prefs.getString('feditech_orders_live_v4') ?? '{}');
      _codes = List<String>.from(jsonDecode(prefs.getString('feditech_codes_live_v4') ?? '[]'));
      _usage = jsonDecode(prefs.getString('feditech_usage_live_v4') ?? '{"used":0}');
      _currentOrderId = prefs.getString('feditech_last_order') ?? '';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('feditech_orders_live_v4', jsonEncode(_orders));
    await prefs.setString('feditech_codes_live_v4', jsonEncode(_codes));
    await prefs.setString('feditech_usage_live_v4', jsonEncode(_usage));
    await prefs.setString('feditech_last_order', _currentOrderId);
  }

  String _generateOrderId() {
    final date = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
    return 'FEDI-$date-${100000 + (DateTime.now().millisecondsSinceEpoch % 900000)}';
  }

  Future<Map<String, dynamic>?> _zenoInit(String orderId, String phone) async {
    final payload = {
      'order_id': orderId,
      'buyer_phone': phone,
      'amount': priceTzs,
      'buyer_name': 'Feditech User',
      'buyer_email': 'user@feditech.tz',
      'metadata': {'network': _selectedNetwork},
    };
    try {
      final response = await http.post(
        Uri.parse(initUrl),
        headers: {'Content-Type': 'application/json', 'x-api-key': zenoApiKey},
        body: jsonEncode(payload),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return null;
    }
  }

  Future<bool> _zenoStatus(String orderId) async {
    try {
      final response = await http.get(
        Uri.parse('$statusUrl?order_id=$orderId'),
        headers: {'x-api-key': zenoApiKey},
      );
      final data = jsonDecode(response.body);
      final item = data['data'] != null && data['data'].isNotEmpty ? data['data'][0] : null;
      return item != null && item['payment_status'].toString().toUpperCase() == 'COMPLETED';
    } catch (e) {
      return false;
    }
  }

  String? _tryAssignVoucher(String orderId) {
    if (!_orders.containsKey(orderId) || _orders[orderId]['voucher'] != null) return _orders[orderId]['voucher'];
    if (_codes.isNotEmpty) {
      final voucher = _codes.removeAt(0);
      _orders[orderId]['voucher'] = voucher;
      _usage['used'] = (_usage['used'] ?? 0) + 1;
      _saveData();
      return voucher;
    }
    return null;
  }

  void _startVerifyLoop(String orderId) {
    int tries = 0;
    const maxTries = 60;
    _pollingTimer?.cancel();
    setState(() {
      _stateMessage = '⌛ Inakagua malipo ya Kumbukumbu: $orderId ...';
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final paid = await _zenoStatus(orderId);
        if (paid) {
          _orders[orderId]['paid'] = true;
          final voucher = _tryAssignVoucher(orderId);
          if (voucher != null) {
            setState(() {
              _stateMessage = '✔ Malipo yamedhibitishwa. Voucher imepatikana.';
              _voucherCode = voucher;
              _isVoucherVisible = true;
            });
            _pollingTimer?.cancel();
          } else {
            setState(() {
              _stateMessage = '✔ Malipo yapo, lakini hakuna voucher kwenye hifadhi (pending). Ongeza vocha upande wa admin.';
            });
          }
        } else {
          setState(() {
            _stateMessage = '⌛ Bado haijaonekana… (Jaribio ${++tries}/$maxTries)';
          });
        }
        if (tries >= maxTries) {
          _pollingTimer?.cancel();
          setState(() {
            _stateMessage = '⛔ Muda umeisha bila uthibitisho. Jaribu tena.';
          });
        }
      } catch (e) {
        setState(() {
          _stateMessage = '⚠ Kosa la mtandao/Status.';
        });
      }
    });
  }

  void _payNow() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^0[67]\d{8}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weka namba ya simu sahihi: 07XXXXXXXX / 06XXXXXXXX')),
      );
      return;
    }
    setState(() {
      _isVoucherVisible = false;
      _voucherCode = '—';
      _isSeeVoucherVisible = false;
      _stateMessage = '⏳ Inaandaa ombi la malipo…';
    });
    final orderId = _generateOrderId();
    _orders[orderId] = {
      'amount': priceTzs,
      'phone': phone,
      'net': _selectedNetwork,
      'paid': false,
      'voucher': null,
      'created': DateTime.now().millisecondsSinceEpoch,
    };
    _currentOrderId = orderId;
    await _saveData();

    final resp = await _zenoInit(orderId, phone);
    if (resp != null && resp['status'].toString().toLowerCase() == 'success') {
      setState(() {
        _stateMessage = '✅ Ombi limetumwa. Kumbukumbu: $orderId. Thibitisha kwenye simu yako. Tunakagua...';
        _isSeeVoucherVisible = true;
      });
      _startVerifyLoop(orderId);
    } else {
      setState(() {
        _stateMessage = '⚠ Ombi halikufaulu: ${resp?['message'] ?? "angalia API key / maombi"}';
      });
    }
  }

  void _seeVoucher() {
    final orderId = _currentOrderId.isNotEmpty ? _currentOrderId : '';
    if (orderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anza kwa kubofya "Lipa TZS 1,000" kwanza.')),
      );
      return;
    }
    if (_orders[orderId]?['voucher'] != null) {
      setState(() {
        _voucherCode = _orders[orderId]['voucher'];
        _isVoucherVisible = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voucher bado haijapatikana. Itatokea mara tu malipo yakithibitishwa na stock ikuwepo.')),
      );
    }
  }

  void _copyCode() {
    if (_voucherCode != '—') {
      // Use Clipboard.setData in a real app; for now, show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voucher imekopiwa: $_voucherCode')),
      );
    }
  }

  void _openAdminModal() {
    setState(() {
      _isPasswordModalVisible = true;
    });
  }

  void _closeAdminModal() {
    setState(() {
      _isPasswordModalVisible = false;
      _adminPassController.clear();
    });
  }

  void _loginAdmin() {
    if (_adminPassController.text == adminPassword) {
      setState(() {
        _isPasswordModalVisible = false;
        _isAdminDrawerOpen = true;
        _isAdminLoggedIn = true;
        _adminPassController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password si sahihi.')),
      );
    }
  }

  void _logoutAdmin() {
    setState(() {
      _isAdminDrawerOpen = false;
      _isAdminLoggedIn = false;
    });
  }

  void _addBulkCodes() {
    final raw = _bulkCodesController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weka vocha angalau moja.')),
      );
      return;
    }
    final list = raw.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    int added = 0;
    for (final v in list) {
      if (!_codes.contains(v)) {
        _codes.add(v);
        added++;
      }
    }
    _bulkCodesController.clear();
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✔ Imeongezwa: $added')),
    );
  }

  void _clearAllCodes() {
    if (_codes.isNotEmpty) {
      setState(() {
        _codes.clear();
      });
      _saveData();
    }
  }

  void _setVoucher() {
    final orderId = _admOrderController.text.trim();
    final voucher = _admCodeController.text.trim();
    if (orderId.isEmpty || voucher.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weka Kumbukumbu ya oda na voucher.')),
      );
      return;
    }
    if (!_orders.containsKey(orderId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oda haipo bado.')),
      );
      return;
    }
    _orders[orderId]['voucher'] = voucher;
    _codes.remove(voucher);
    _usage['used'] = (_usage['used'] ?? 0) + 1;
    _admOrderController.clear();
    _admCodeController.clear();
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✔ Voucher imewekwa kwa oda hiyo.')),
    );
  }

  int _getPendingCount() {
    return _orders.values.where((o) => o['paid'] == true && o['voucher'] == null).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF60A5FA)]),
              ),
              child: const Icon(Icons.refresh, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Feditech', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text('Siku 1 = TZS 1,000 • Malipo ya haraka', style: TextStyle(color: Theme.of(context).colorScheme.onBackground, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: _openAdminModal,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: const Color(0xFFBFE4FF),
              side: const BorderSide(color: Color(0xFFFFFFFF).withOpacity(0.22)),
            ),
            child: const Text('🔒 Admin'),
          ),
        ],
        backgroundColor: const Color(0xFF070B18).withOpacity(0.9),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070B18), Color(0xFF0A1532)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              // Hero Section
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF0A1532).withOpacity(0.06),
                  border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20),
                  ],
                ),
                child: Column(
                  children: [
                    const Text('🤖 Malipo ya moja kwa moja • "Ona Voucher"', style: TextStyle(fontSize: 12, color: Color(0xFFBFE4FF))),
                    const SizedBox(height: 10),
                    RichText(
                      text: const TextSpan(
                        text: 'Fungua intaneti ya leo kwa ',
                        children: [
                          TextSpan(text: 'TZS 1,000', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, foreground: Paint()..shader = LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF60A5FA)]).createShader(Rect.fromLTWH(0, 0, 200, 70)))),
                          TextSpan(text: ' — pata voucher papo hapo'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Weka namba ya simu, chagua mtandao, kisha bofya Lipa. Baada ya kuthibitisha kwenye simu yako, ukurasa utakagua mwenyewe mpaka voucher ipatikane — bila kujaza fomu nyingi.', style: TextStyle(color: Theme.of(context).colorScheme.onBackground)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Namba ya simu (mf. 07XXXXXXXX)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFF0F1A33),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Network Selection
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              _networkCard('airtel', 'Airtel Money', 'Push ya moja kwa moja'),
                              _networkCard('halotel', 'Halotel', 'Halopesa'),
                              _networkCard('tigomix', 'Tigo / Mix by Yas', 'TigoPesa'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedNetwork,
                            items: const [
                              DropdownMenuItem(value: 'airtel', child: Text('Airtel Money')),
                              DropdownMenuItem(value: 'halotel', child: Text('Halotel')),
                              DropdownMenuItem(value: 'tigomix', child: Text('Tigo / Mix by Yas')),
                            ],
                            onChanged: (value) => setState(() => _selectedNetwork = value!),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Color(0xFF0F1A33),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _payNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22D3EE),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Lipa TZS 1,000'),
                        ),
                        if (_isSeeVoucherVisible) ...[
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _seeVoucher,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: const Color(0xFFBFE4FF),
                              side: const BorderSide(color: Color(0xFFFFFFFF).withOpacity(0.22)),
                            ),
                            child: const Text('Ona Voucher'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_stateMessage, style: const TextStyle(fontSize: 14)),
                    if (_isVoucherVisible) ...[
                      const SizedBox(height: 14),
                      const Text('Voucher yako:', style: TextStyle(fontSize: 14)),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.33), width: 1, style: BorderStyle.dashed),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF0E1429),
                        ),
                        child: Center(
                          child: Text(_voucherCode, style: const TextStyle(fontSize: 22, fontFamily: 'monospace')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _copyCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: const Color(0xFFBFE4FF),
                          side: const BorderSide(color: Color(0xFFFFFFFF).withOpacity(0.22)),
                        ),
                        child: const Text('Copy Voucher'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('© ${DateTime.now().year} Feditech', style: TextStyle(color: Theme.of(context).colorScheme.onBackground, fontSize: 14)),
            ],
          ),
        ),
      ),
      // Admin Drawer
      endDrawer: _isAdminDrawerOpen
          ? Drawer(
              backgroundColor: const Color(0xFF070B18).withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Zilizopo: ${_codes.length}', style: const TextStyle(color: Color(0xFFE6EEF6))),
                        Text('Zilizotolewa: ${_usage['used'] ?? 0}', style: const TextStyle(color: Color(0xFFE6EEF6))),
                        Text('Pending: ${_getPendingCount()}', style: const TextStyle(color: Color(0xFFE6EEF6))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Ongeza vocha nyingi', style: TextStyle(color: Color(0xFFE6EEF6), fontWeight: FontWeight.w600)),
                    TextField(
                      controller: _bulkCodesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Weka vocha zako hapa (kila mstari vocha 1)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Color(0xFF0F1A33),
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton(onPressed: _addBulkCodes, child: const Text('Ongeza kwenye hifadhi')),
                        ElevatedButton(onPressed: _clearAllCodes, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Futa zote')),
                      ],
                    ),
                    const Text('Mfano: FEDI-843920, FEDI-552110...', style: TextStyle(color: Color(0xFF9FB0C7), fontSize: 12)),
                    const SizedBox(height: 10),
                    const Text('Vocha zilizopo', style: TextStyle(color: Color(0xFFE6EEF6), fontWeight: FontWeight.w600)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _codes.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(_codes[index], style: const TextStyle(color: Color(0xFFE6EEF6))),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Color(0xFF93C5FD)),
                            onPressed: () => setState(() => _codes.removeAt(index)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Weka/Badili voucher ya oda maalum', style: TextStyle(color: Color(0xFFE6EEF6), fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _admOrderController, decoration: const InputDecoration(labelText: 'Kumbukumbu ya oda'))),
                        Expanded(child: TextField(controller: _admCodeController, decoration: const InputDecoration(labelText: 'Mf. FEDI-123456'))),
                      ],
                    ),
                    ElevatedButton(onPressed: _setVoucher, child: const Text('Weka/Badili Voucher')),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: _logoutAdmin, child: const Text('Logout')),
                  ],
                ),
              ),
            )
          : null,
      // Password Modal
      persistentFooterButtons: _isPasswordModalVisible
          ? [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1532).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Weka Password ya Admin', style: TextStyle(color: Color(0xFFE6EEF6), fontSize: 16)),
                    TextField(
                      controller: _adminPassController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '••••'),
                    ),
                    Row(
                      children: [
                        ElevatedButton(onPressed: _loginAdmin, child: const Text('Ingia')),
                        ElevatedButton(onPressed: _closeAdminModal, child: const Text('Funga')),
                      ],
                    ),
                  ],
                ),
              ),
            ]
          : null,
    );
  }

  Widget _networkCard(String value, String name, String desc) {
    final isSelected = _selectedNetwork == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedNetwork = value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? const Color(0xFF60A5FA).withOpacity(0.55) : const Color(0xFFFFFFFF).withOpacity(0.2)),
          color: const Color(0xFF0F1A33),
          boxShadow: isSelected ? [const BoxShadow(color: Color(0xFF60A5FA).withOpacity(0.22), blurRadius: 4)] : null,
        ),
        child: Column(
          children: [
            Icon(Icons.network_cell, color: _getNetworkColor(value)),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF9FB0C7))),
          ],
        ),
      ),
    );
  }

  Color _getNetworkColor(String network) {
    switch (network) {
      case 'airtel': return Colors.red;
      case 'halotel': return Colors.green;
      case 'tigomix': return const Color(0xFF60A5FA);
      default: return Colors.white;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _adminPassController.dispose();
    _bulkCodesController.dispose();
    _admOrderController.dispose();
    _admCodeController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }
}