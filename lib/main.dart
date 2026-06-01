// main.dart
//
// Firebase Auth SDK'sı bypass edildi (macOS keychain sorunu nedeniyle).
// Auth state RestAuthService üzerinden yönetilir.
//
// Akış:
//   1. WidgetsFlutterBinding + Firebase.initializeApp (database SDK için lazım)
//   2. RestAuthService.init() çağrılır → refresh token varsa otomatik login
//   3. ListenableBuilder ile UI auth state'i izler
//   4. Login varsa rol kontrolü ile uygun panele, yoksa AuthPage'e

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options.dart';
import 'auth_page.dart';
import 'ogrenci_panel/ogrenci_panel_base.dart';
import 'Akademisyen_panel/akademisyen_panel.dart';
import 'idari_panel/idare_panel.dart';
import 'services/rest_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await RestAuthService.instance.init();
  runApp(const UniversiteSistemi());
}

class UniversiteSistemi extends StatelessWidget {
  const UniversiteSistemi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Üniversite Yönetim Paneli',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005A71)),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: RestAuthService.instance,
        builder: (context, _) {
          final auth = RestAuthService.instance;
          if (!auth.isInitialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (auth.isLoggedIn) {
            return RoleBasedRedirect(uid: auth.currentUid!);
          }
          return const AuthPage();
        },
      ),
    );
  }
}

/// Login olmuş kullanıcının rolüne göre uygun panele yönlendirir.
class RoleBasedRedirect extends StatefulWidget {
  final String uid;
  const RoleBasedRedirect({super.key, required this.uid});

  @override
  State<RoleBasedRedirect> createState() => _RoleBasedRedirectState();
}

class _RoleBasedRedirectState extends State<RoleBasedRedirect> {
  late Future<Widget> _hedefSayfa;

  @override
  void initState() {
    super.initState();
    _hedefSayfa = _rolKontroluYap();
  }

  Future<Widget> _rolKontroluYap() async {
    // Önce academic_users altına bak
    final academic = await FirebaseDatabase.instance
        .ref()
        .child('academic_users/${widget.uid}/roller')
        .get();
    final roller = <String>[];
    if (academic.exists && academic.value is Map) {
      (academic.value as Map).forEach((k, v) {
        if (v == true) roller.add(k.toString());
      });
    } else {
      // Sonra users altına bak (öğrenci)
      final student = await FirebaseDatabase.instance
          .ref()
          .child('users/${widget.uid}/roller')
          .get();
      if (student.exists && student.value is Map) {
        (student.value as Map).forEach((k, v) {
          if (v == true) roller.add(k.toString());
        });
      }
    }

    if (roller.isEmpty) {
      // Roller bulunamadı - signout edip auth ekranına dön
      await RestAuthService.instance.signOut();
      return const AuthPage();
    }

    if (roller.length == 1) {
      return _panelFor(roller.first);
    }

    // Birden fazla rol → seçim ekranı
    return _RolSecimSayfasi(roller: roller);
  }

  Widget _panelFor(String rol) {
    switch (rol) {
      case 'akademisyen':
        return const AkademisyenPanel();
      case 'idare':
        return const IdarePanel();
      default:
        return OgrenciPanelBase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _hedefSayfa,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data!;
      },
    );
  }
}

/// Birden fazla role sahip kullanıcıya panel seçimi sunan ekran.
class _RolSecimSayfasi extends StatelessWidget {
  final List<String> roller;
  const _RolSecimSayfasi({required this.roller});

  @override
  Widget build(BuildContext context) {
    const neu = Color(0xFF005A71);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel Seçimi"),
        backgroundColor: neu,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => RestAuthService.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Hangi panele gitmek istiyorsunuz?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            ...roller.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neu,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: () {
                        Widget sayfa;
                        switch (r) {
                          case 'akademisyen':
                            sayfa = const AkademisyenPanel();
                            break;
                          case 'idare':
                            sayfa = const IdarePanel();
                            break;
                          default:
                            sayfa = OgrenciPanelBase();
                        }
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => sayfa));
                      },
                      child: Text(r.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
