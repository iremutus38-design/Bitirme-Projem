import 'package:flutter/material.dart';
import '../models/student_model.dart';
import '../services/student_api_service.dart';

class TumOgrencilerSayfasi extends StatefulWidget {
  const TumOgrencilerSayfasi({super.key});

  @override
  State<TumOgrencilerSayfasi> createState() => _TumOgrencilerSayfasiState();
}

class _TumOgrencilerSayfasiState extends State<TumOgrencilerSayfasi> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StudentApiService _apiService = StudentApiService();
  final Color neuColor = const Color(0xFF005A71);
  final TextEditingController _searchController = TextEditingController(); 
  
  List<Student> _allStudents = [];
  List<Student> _filteredStudents = []; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _verileriGetir();
  }

  void _verileriGetir() async {
    setState(() => _isLoading = true);
    final data = await _apiService.fetchAllStudentsFromFirebase();
    setState(() {
      _allStudents = data;
      _filteredStudents = data; 
      _isLoading = false;
    });
  }

  void _filterStudents(String query) {
    setState(() {
      _filteredStudents = _allStudents.where((s) {
        final searchLower = query.toLowerCase();
        return s.adSoyad.toLowerCase().contains(searchLower) || 
               s.id.contains(query) || 
               s.tcNo.contains(query);
      }).toList();
    });
  }

void _ogrencileriSenkronizeEt() async {
  // 1. Durum Takipçileri
  final ValueNotifier<int> progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>("Hazırlanıyor...");
  final ValueNotifier<bool> isFinished = ValueNotifier<bool>(false);
  int totalToUpload = 0;

  // 2. ÖNCE DİYALOĞU GÖSTER (HİÇBİR İŞLEM YAPMADAN)
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false, // Geri tuşuyla kapatılmasın
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: ValueListenableBuilder<bool>(
          valueListenable: isFinished,
          builder: (context, finished, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                finished 
                  ? const Icon(Icons.check_circle, color: Colors.green, size: 60)
                  : const CircularProgressIndicator(strokeWidth: 5),
                const SizedBox(height: 25),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, _) => Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 10),
                if (!finished)
                  ValueListenableBuilder<int>(
                    valueListenable: progressNotifier,
                    builder: (context, val, _) => Text(
                      totalToUpload > 0 ? "$val / $totalToUpload" : "Dosya okunuyor...",
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neuColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _verileriGetir(); // Listeyi yenile
                      },
                      child: const Text("Kapat", style: TextStyle(color: Colors.white)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  // 3. KRİTİK NOKTA: UI'ın diyaloğu çizmesi için çok kısa bir süre bekle
  await Future.delayed(const Duration(milliseconds: 50));

  try {
    // 4. EXCEL OKUMA BAŞLIYOR
    statusNotifier.value = "Excel dosyası analiz ediliyor...";
    final list = await _apiService.fetchStudentsFromExcel();
    
    if (list.isEmpty) {
      Navigator.pop(context);
      return;
    }

    totalToUpload = list.length;
    statusNotifier.value = "Veriler Firebase'e aktarılıyor...";

    // 5. FIREBASE AKTARIMI (Burada terminaldeki akışı anlık ekrana basar)
    await _apiService.syncStudentsToFirebase(
      list,
      onProgress: (count) {
        progressNotifier.value = count;
      },
    );

    // 6. BİTİŞ
    statusNotifier.value = "İşlem Başarıyla Tamamlandı!";
    isFinished.value = true;

  } catch (e) {
    if (Navigator.canPop(context)) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
    );
  }
}
  
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Öğrenci Veritabanı (${_filteredStudents.length}/${_allStudents.length})", 
          style: const TextStyle(color: Colors.white, fontSize: 14)
        ),
        backgroundColor: neuColor,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: false,
        actions: [
          // YENİ EKLENEN YÜKLEME BUTONU
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _ogrencileriSenkronizeEt,
            tooltip: "Excel Yükle",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _verileriGetir,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterStudents,
                    decoration: const InputDecoration(
                      hintText: "İsim, No veya TC ile ara...",
                      prefixIcon: Icon(Icons.search, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(text: "Tümü"),
                  Tab(text: "1. Sınıf"),
                  Tab(text: "2. Sınıf"),
                  Tab(text: "3. Sınıf"),
                  Tab(text: "4. Sınıf"),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStudentList(null), 
                _buildStudentList(1),    
                _buildStudentList(2),    
                _buildStudentList(3),    
                _buildStudentList(4),    
              ],
            ),
    );
  }

  Widget _buildStudentList(int? sinifFiltresi) {
    final liste = sinifFiltresi == null 
        ? _filteredStudents 
        : _filteredStudents.where((s) => s.sinif == sinifFiltresi).toList();

    if (liste.isEmpty) {
      return const Center(child: Text("Sonuç bulunamadı."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: liste.length,
      itemBuilder: (context, index) {
        final ogrenci = liste[index];
        final rawData = ogrenci.toJson();
        bool isRegistered = rawData['kayit_durumu'] == 'aktif' || rawData['kayit_durumu'] == 'tamamlandı';

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isRegistered ? Colors.green : neuColor,
              child: Text("${ogrenci.sinif}", style: const TextStyle(color: Colors.white)),
            ),
            title: Text(ogrenci.adSoyad, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${ogrenci.bolum}\nID: ${ogrenci.id}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isRegistered ? Icons.check_circle : Icons.hourglass_empty,
                  color: isRegistered ? Colors.green : Colors.orange,
                ),
                Text(
                  isRegistered ? "Aktif" : "Beklemede",
                  style: TextStyle(
                    fontSize: 10, 
                    color: isRegistered ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}