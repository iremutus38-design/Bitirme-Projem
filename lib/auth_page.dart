// auth_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/rest_auth_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final Color neuColor = const Color(0xFF005A71);
  final _noOrEmailController = TextEditingController();
  final _passwordController  = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading      = false;
  bool _sifreGizli     = true;
  bool _dropdownAcik   = false;

  List<String> _kayitliHesaplar = [];

  @override
  void initState() {
    super.initState();
    _kayitliHesaplariYukle();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _kayitliHesaplar.isNotEmpty) {
        setState(() => _dropdownAcik = true);
      }
    });
  }

  @override
  void dispose() {
    _noOrEmailController.dispose();
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _kayitliHesaplariYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _kayitliHesaplar = prefs.getStringList('saved_accounts') ?? [];
    });
  }

  Future<void> _hesapKaydet(String deger) async {
    if (deger.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final liste = prefs.getStringList('saved_accounts') ?? [];
    if (!liste.contains(deger)) {
      liste.insert(0, deger);
      if (liste.length > 5) liste.removeLast(); // max 5 hesap
      await prefs.setStringList('saved_accounts', liste);
      setState(() => _kayitliHesaplar = liste);
    }
  }

  Future<void> _hesapSil(String deger) async {
    final prefs = await SharedPreferences.getInstance();
    final liste = prefs.getStringList('saved_accounts') ?? [];
    liste.remove(deger);
    await prefs.setStringList('saved_accounts', liste);
    setState(() => _kayitliHesaplar = liste);
  }

  String _emailDuzenle(String email) {
    const tr = ['ı', 'ğ', 'ü', 'ş', 'ö', 'ç', 'İ', 'Ğ', 'Ü', 'Ş', 'Ö', 'Ç'];
    const en = ['i', 'g', 'u', 's', 'o', 'c', 'i', 'g', 'u', 's', 'o', 'c'];
    String temiz = email.trim().toLowerCase();
    for (int i = 0; i < tr.length; i++) {
      temiz = temiz.replaceAll(tr[i], en[i]);
    }
    return temiz;
  }

  Future<void> _girisYap() async {
    final input    = _noOrEmailController.text.trim();
    final password = _passwordController.text.trim();
    if (input.isEmpty || password.isEmpty) {
      _mesaj("Lütfen tüm alanları doldurun."); return;
    }
    setState(() { _isLoading = true; _dropdownAcik = false; });
    try {
      String? targetEmail;
      if (input.contains("@")) {
        targetEmail = _emailDuzenle(input);
      } else {
        targetEmail = await _emailFromOkulNo(input);
      }
      if (targetEmail == null) {
        setState(() => _isLoading = false);
        _mesaj("Kullanıcı bulunamadı!"); return;
      }
      final result = await RestAuthService.instance.signInWithEmail(targetEmail, password);
      setState(() => _isLoading = false);
      if (result.success) {
        await _hesapKaydet(input); // başarılıysa kaydet
      } else {
        _mesaj(result.message);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _mesaj("Beklenmedik hata: $e");
    }
  }

  Future<String?> _emailFromOkulNo(String okulNo) async {
    final s = await FirebaseDatabase.instance
        .ref().child('users').orderByChild('okul_no').equalTo(okulNo).get();
    if (s.exists && s.value is Map) {
      final email = (s.value as Map).values.first['email']?.toString();
      if (email != null && email.isNotEmpty) return email;
    }
    final a = await FirebaseDatabase.instance
        .ref().child('academic_users').orderByChild('okul_no').equalTo(okulNo).get();
    if (a.exists && a.value is Map) {
      final email = (a.value as Map).values.first['email']?.toString();
      if (email != null && email.isNotEmpty) return email;
    }
    return null;
  }

  void _mesaj(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: neuColor, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _dropdownAcik = false),
      child: Scaffold(
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: neuColor))
            : SingleChildScrollView(
                child: Column(children: [
                  _buildHeader(),
                  Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Giriş Yap",
                            style: TextStyle(color: neuColor, fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text("Öğrenci, akademisyen ve idari kullanıcılar için ortak giriş.",
                            style: TextStyle(color: neuColor.withOpacity(0.7), fontSize: 13)),
                        const SizedBox(height: 22),

                        // ── E-posta / No alanı + dropdown ──
                        _buildHesapAlani(),
                        const SizedBox(height: 15),

                        // ── Şifre ──
                        TextField(
                          controller: _passwordController,
                          obscureText: _sifreGizli,
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            prefixIcon: Icon(Icons.lock_outline, color: neuColor),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _sifreGizli ? Icons.visibility_off : Icons.visibility,
                                color: Colors.grey, size: 20,
                              ),
                              onPressed: () => setState(() => _sifreGizli = !_sifreGizli),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),

                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: neuColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: _girisYap,
                            child: const Text("GİRİŞ YAP",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoNotu(),
                      ],
                    ),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _buildHesapAlani() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _noOrEmailController,
          focusNode: _focusNode,
          keyboardType: TextInputType.emailAddress,
          onChanged: (val) {
            if (_kayitliHesaplar.isNotEmpty) {
              setState(() => _dropdownAcik = val.isEmpty || _focusNode.hasFocus);
            }
          },
          onTap: () {
            if (_kayitliHesaplar.isNotEmpty) setState(() => _dropdownAcik = true);
          },
          decoration: InputDecoration(
            labelText: 'Öğrenci No / E-posta',
            prefixIcon: Icon(Icons.alternate_email, color: neuColor),
            suffixIcon: _noOrEmailController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    onPressed: () {
                      _noOrEmailController.clear();
                      setState(() => _dropdownAcik = _kayitliHesaplar.isNotEmpty);
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),

        // ── Kayıtlı hesaplar dropdown ──
        if (_dropdownAcik && _kayitliHesaplar.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3))],
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text('Kayıtlı hesaplar',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ),
                ..._kayitliHesaplar.map((hesap) => InkWell(
                  onTap: () {
                    _noOrEmailController.text = hesap;
                    _noOrEmailController.selection = TextSelection.fromPosition(
                        TextPosition(offset: hesap.length));
                    setState(() => _dropdownAcik = false);
                    FocusScope.of(context).requestFocus(_focusNode);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 18, color: neuColor.withOpacity(0.7)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(hesap, style: const TextStyle(fontSize: 14)),
                      ),
                      GestureDetector(
                        onTap: () => _hesapSil(hesap),
                        child: const Icon(Icons.close, size: 16, color: Colors.grey),
                      ),
                    ]),
                  ),
                )),
                const SizedBox(height: 4),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: neuColor,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(80)),
      ),
      child: const Center(
        child: Text("NEÜ BİLGİ SİSTEMİ",
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildInfoNotu() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: neuColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: neuColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: neuColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Hesabınız yoksa öğrenci işlerine başvurun. Kayıt işlemi idari panelden yapılır.",
              style: TextStyle(fontSize: 12, color: neuColor),
            ),
          ),
        ],
      ),
    );
  }
}
