import cv2
import face_recognition
import firebase_admin
from firebase_admin import credentials, db
from datetime import datetime
import numpy as np

# Firebase bağlantısı
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://finalproject-eb873-default-rtdb.firebaseio.com'
})

def kayitli_yuzleri_yukle():
    """Firebase'den tüm kayıtlı öğrencilerin yüz verilerini yükle"""
    print("Öğrenci yüz verileri yükleniyor...")
    users_ref = db.reference('users')
    users = users_ref.get()
    
    kayitli_encodings = []
    kayitli_bilgiler = []
    
    if users:
        for uid, data in users.items():
            if 'face_encoding' in data:
                encoding = np.array(data['face_encoding'])
                kayitli_encodings.append(encoding)
                kayitli_bilgiler.append({
                    'uid': uid,
                    'ad_soyad': data.get('ad_soyad', 'Bilinmiyor'),
                    'okul_no': data.get('okul_no', '')
                })
    
    print(f"{len(kayitli_encodings)} öğrenci yüklendi.")
    return kayitli_encodings, kayitli_bilgiler

def yoklama_kaydet(uid, ad_soyad, ders_id):
    """Öğrencinin yoklamasını Firebase'e kaydet"""
    bugun = datetime.now().strftime('%Y-%m-%d')
    saat = datetime.now().strftime('%H:%M:%S')
    
    yoklama_ref = db.reference(f'attendance/{ders_id}/{bugun}/{uid}')
    mevcut = yoklama_ref.get()
    
    if not mevcut:
        yoklama_ref.set({
            'ad_soyad': ad_soyad,
            'giris_saati': saat,
            'yuz_tanima': True,
            'mobil_onay': False,
            'durum': 'giris_yapti'
        })
        print(f"✓ {ad_soyad} - Yoklama kaydedildi! ({saat})")
        return True
    else:
        print(f"→ {ad_soyad} - Zaten kayıtlı.")
        return False

def yoklama_baslat(ders_id):
    """Ana yoklama döngüsü"""
    
    # Kayıtlı yüzleri yükle
    kayitli_encodings, kayitli_bilgiler = kayitli_yuzleri_yukle()
    
    if not kayitli_encodings:
        print("HATA: Hiç kayıtlı öğrenci yüzü bulunamadı!")
        return
    
    print(f"\nDers ID: {ders_id}")
    print("Kamera açılıyor... Öğrenciler kameraya geçsin.")
    print("Çıkmak için 'Q' tuşuna basın.\n")
    
    kamera = cv2.VideoCapture(0)
    
    if not kamera.isOpened():
        print("HATA: Kamera açılamadı!")
        return
    
    taninan_ogrenciler = set()
    
    while True:
        ret, frame = kamera.read()
        if not ret:
            break
        
        # Performans için küçült
        kucuk_frame = cv2.resize(frame, (0, 0), fx=0.25, fy=0.25)
        rgb_kucuk = cv2.cvtColor(kucuk_frame, cv2.COLOR_BGR2RGB)
        
        # Yüzleri tespit et
        yuz_konumlari = face_recognition.face_locations(rgb_kucuk)
        yuz_encodings = face_recognition.face_encodings(rgb_kucuk, yuz_konumlari)
        
        for encoding, (top, right, bottom, left) in zip(yuz_encodings, yuz_konumlari):
            top *= 4; right *= 4; bottom *= 4; left *= 4
            
            # Kayıtlı yüzlerle karşılaştır
            eslesme = face_recognition.compare_faces(kayitli_encodings, encoding, tolerance=0.5)
            mesafe = face_recognition.face_distance(kayitli_encodings, encoding)
            
            ad = "Tanınamadı"
            renk = (0, 0, 255)  # Kırmızı
            
            if True in eslesme:
                en_iyi = np.argmin(mesafe)
                if eslesme[en_iyi]:
                    ogrenci = kayitli_bilgiler[en_iyi]
                    ad = ogrenci['ad_soyad']
                    renk = (0, 255, 0)  # Yeşil
                    
                    # İlk kez tanındıysa yoklamayı kaydet
                    if ogrenci['uid'] not in taninan_ogrenciler:
                        taninan_ogrenciler.add(ogrenci['uid'])
                        yoklama_kaydet(ogrenci['uid'], ad, ders_id)
            
            # Ekranda göster
            cv2.rectangle(frame, (left, top), (right, bottom), renk, 2)
            cv2.rectangle(frame, (left, bottom - 30), (right, bottom), renk, cv2.FILLED)
            cv2.putText(frame, ad, (left + 6, bottom - 8),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
        
        # Tanınan öğrenci sayısını göster
        cv2.putText(frame, f"Taninan: {len(taninan_ogrenciler)} ogrenci",
                   (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
        
        cv2.imshow(f"Yoklama - Ders: {ders_id}", frame)
        
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
    
    kamera.release()
    cv2.destroyAllWindows()
    print(f"\nYoklama tamamlandı. Toplam {len(taninan_ogrenciler)} öğrenci kaydedildi.")

def main():
    print("=" * 40)
    print("   YOKLAMA SİSTEMİ")
    print("=" * 40)
    
    ders_id = input("\nDers ID girin (örn: BIL101): ").strip()
    
    if not ders_id:
        print("HATA: Ders ID boş olamaz!")
        return
    
    yoklama_baslat(ders_id)

if __name__ == "__main__":
    main()