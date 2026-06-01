import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class IdariAyarlar extends StatefulWidget {
  const IdariAyarlar({super.key});

  @override
  State<IdariAyarlar> createState() => _IdariAyarlarState();
}

class _IdariAyarlarState extends State<IdariAyarlar> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref().child('academic_users');
  final Color neuColor = const Color(0xFF005A71);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Yetkili Yönetimi"),
        backgroundColor: neuColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _yetkiliEkleDiyalog(),
          )
        ],
      ),
      body: StreamBuilder(
        stream: _dbRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) return Center(child: Text("Hata: ${snapshot.error}"));
          
          List<Map<String, dynamic>> filtrelenmisListe = [];

          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final Map<dynamic, dynamic> data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
            
            data.forEach((key, value) {
              final hoca = Map<String, dynamic>.from(value);
              String ad = (hoca['ad_soyad'] ?? "").toString().toUpperCase();
              bool isIdari = hoca['roller']?['idari'] == true;
              bool isAkademisyen = hoca['roller']?['akademisyen'] == true;
              
              // HATA BURADA DÜZELTİLDİ: Değişken ismi birleşik (sabitHocaMi)
              bool sabitHocaMi = ad.contains("MEHMET KAYRICI") || 
                                ad.contains("YUSUF UZUN") || 
                                ad.contains("KUMCU");

              if (isIdari || sabitHocaMi) {
                filtrelenmisListe.add({
                  "key": key,
                  "unvan": hoca['unvan'] ?? "",
                  "ad_soyad": ad,
                  "akademisyen": isAkademisyen,
                });
              }
            });
          }

          if (filtrelenmisListe.isEmpty) {
            return const Center(child: Text("Gösterilecek yetkili bulunamadı."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: filtrelenmisListe.length,
            itemBuilder: (context, index) {
              final user = filtrelenmisListe[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: user['akademisyen'] ? Colors.purple.shade100 : Colors.blue.shade100,
                    child: Icon(user['akademisyen'] ? Icons.school : Icons.person, color: neuColor),
                  ),
                  title: Text(user['ad_soyad'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${user['unvan']} ${user['akademisyen'] ? '(Akademisyen)' : '(İdari Personel)'}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _dbRef.child(user['key']).remove(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _yetkiliEkleDiyalog() {
    final nameCtrl = TextEditingController();
    final unvanCtrl = TextEditingController();
    bool isAkademisyen = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Yeni Yetkili Ekle"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: unvanCtrl, decoration: const InputDecoration(labelText: "Unvan (Prof. Dr. vb.)")),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Ad Soyad")),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Akademisyen mi?", style: TextStyle(fontSize: 14)),
                  value: isAkademisyen,
                  activeColor: neuColor,
                  onChanged: (val) => setDialogState(() => isAkademisyen = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: neuColor),
              onPressed: () async {
                final isim = nameCtrl.text.trim().toUpperCase();
                if (isim.isEmpty) return;

                try {
                  await _dbRef.push().set({
                    "ad_soyad": isim,
                    "unvan": unvanCtrl.text.trim(),
                    "roller": {
                      "akademisyen": isAkademisyen,
                      "idari": true 
                    }
                  });
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  debugPrint("Ekleme Hatası: $e");
                }
              },
              child: const Text("Sisteme Ekle", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}