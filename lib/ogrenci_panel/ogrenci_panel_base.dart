// ogrenci_panel_base.dart

import 'package:flutter/material.dart';
import 'package:bitirme_projesi/services/rest_auth_service.dart';
import 'package:bitirme_projesi/ogrenci_panel/anasayfa_view.dart';
import 'package:bitirme_projesi/ogrenci_panel/ders_sinav_view.dart';
import 'package:bitirme_projesi/ogrenci_panel/profil_view.dart';

class OgrenciPanelBase extends StatefulWidget {
  const OgrenciPanelBase({super.key});

  @override
  State<OgrenciPanelBase> createState() => _OgrenciPanelBaseState();
}

class _OgrenciPanelBaseState extends State<OgrenciPanelBase> {
  int _selectedIndex = 0;
  static const Color _neu = Color(0xFF005A71);

  static const List<Widget> _pages = [
    AnasayfaView(),
    DersSinavView(),
    ProfilView(),
  ];

  static const List<String> _titles = [
    'Anasayfa',
    'Derslerim',
    'Profil',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _neu,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Çıkış yap',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Çıkış yap'),
                  content: const Text('Oturumu kapatmak istiyor musunuz?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Çıkış')),
                  ],
                ),
              );
              if (confirm == true) {
                await RestAuthService.instance.signOut();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        indicatorColor: _neu.withOpacity(0.15),
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: _neu),
            label: 'Anasayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: _neu),
            label: 'Derslerim',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: _neu),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
