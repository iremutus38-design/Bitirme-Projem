import cv2
import face_recognition
import firebase_admin
from firebase_admin import credentials, db
import numpy as np
import os

# Firebase bağlantısı
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://finalproject-eb873-default-rtdb.firebaseio.com'
})

def ogrenci_bul(girilen_no):
    """Önce aktif hesaplara (users / academic_users), sonra ön kayıtlara bak.
    Eşleşmede uid, okul_no veya tc_no kontrol edilir.
    Dönüş: (node_name, key, data) — yüz encoding'i hangi node'a yazacağımızı bilmek için node_name döndürürüz.
    """
    girilen_no = str(girilen_no).strip()

    # 1) Aktif hesaplar: önce öğrenci, sonra akademisyen
    for node_name in ('users', 'academic_users'):
        try:
            kayitlar = db.reference(node_name).get()
        except Exception as e:
            print(f"[Uyarı] {node_name} okunamadı: {e}")
            kayitlar = None

        if not kayitlar:
            continue

        for uid, data in kayitlar.items():
            if not isinstance(data, dict):
                continue
            if (str(uid) == girilen_no or
                str(data.get('okul_no', '')) == girilen_no or
                str(data.get('tc_no', '')) == girilen_no):
                print(f"[Bulundu: {node_name}/{uid}]")
                return node_name, uid, data

    # 2) Ön kayıtlar (henüz Flutter'dan kayıt olmamış öğrenciler)
    try:
        on_kayitlar = db.reference('on_kayitlar').get()
    except Exception as e:
        print(f"[Uyarı] on_kayitlar okunamadı: {e}")
        on_kayitlar = None

    if on_kayitlar:
        for tc, data in on_kayitlar.items():
            if not isinstance(data, dict):
                continue
            if (str(tc) == girilen_no or
                str(data.get('okul_no', '')) == girilen_no or
                str(data.get('tc_no', '')) == girilen_no):
                print(f"[Bulundu: on_kayitlar/{tc}] (Henüz aktif hesap yok — encoding ön kayda yazılacak, hesap aktifleşince Flutter taşıyacak)")
                return 'on_kayitlar', tc, data

    print("Hiç kayıt bulunamadı. ID/TC/okul_no doğru mu, ön kayıt yapılmış mı kontrol edin.")
    return None, None, None

def yuz_kaydet(girilen_no):
    node_name, uid, ogrenci = ogrenci_bul(girilen_no)

    if not ogrenci:
        print(f"HATA: {girilen_no} numaralı öğrenci bulunamadı!")
        return False
    
    print(f"\nÖğrenci bulundu: {ogrenci.get('ad_soyad')}")
    print("Kamera açılıyor... Yüzünüzü kameraya bakın.")
    print("'K' tuşuna basarak yüzü kaydedin, 'Q' ile çıkın.\n")
    
    kamera = cv2.VideoCapture(0)
    
    if not kamera.isOpened():
        print("HATA: Kamera açılamadı!")
        return False
    
    kayit_yapildi = False
    
    while True:
        ret, frame = kamera.read()
        if not ret:
            print("HATA: Kameradan görüntü alınamadı!")
            break
        
        kucuk_frame = cv2.resize(frame, (0, 0), fx=0.25, fy=0.25)
        rgb_kucuk_frame = cv2.cvtColor(kucuk_frame, cv2.COLOR_BGR2RGB)
        yuz_konumlari = face_recognition.face_locations(rgb_kucuk_frame)
        
        for (top, right, bottom, left) in yuz_konumlari:
            top *= 4; right *= 4; bottom *= 4; left *= 4
            cv2.rectangle(frame, (left, top), (right, bottom), (0, 255, 0), 2)
            cv2.putText(frame, "Yuz Algilandi - K: Kaydet", 
                       (left, top - 10), cv2.FONT_HERSHEY_SIMPLEX, 
                       0.6, (0, 255, 0), 2)
        
        if not yuz_konumlari:
            cv2.putText(frame, "Yuz Algilanamadi", (20, 40), 
                       cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
        
        cv2.imshow(f"Yuz Kayit - {ogrenci.get('ad_soyad')}", frame)
        
        tus = cv2.waitKey(1) & 0xFF

        # Hem 'k' hem boşluk tuşu kayıt için kabul edilir
        if tus in (ord('k'), ord('K'), ord(' ')) and yuz_konumlari:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            encodings = face_recognition.face_encodings(rgb_frame, yuz_konumlari)

            if encodings:
                encoding = encodings[0].tolist()
                # Encoding'i bulduğumuz node'un altına yaz (users / academic_users / on_kayitlar)
                db.reference(f'{node_name}/{uid}').update({
                    'face_encoding': encoding
                })
                print(f"✓ {ogrenci.get('ad_soyad')} için yüz başarıyla kaydedildi! "
                      f"(yazıldığı yer: {node_name}/{uid})")
                kayit_yapildi = True
                break

        elif tus == ord('q'):
            print("Kayıt iptal edildi.")
            break
    
    kamera.release()
    cv2.destroyAllWindows()
    return kayit_yapildi

def main():
    print("=" * 40)
    print("   YÜZ KAYIT SİSTEMİ")
    print("=" * 40)
    print("NOT: ID (örn: 23370031021) veya TC No (örn: 10439520116) girebilirsiniz.")
    
    while True:
        girilen_no = input("\nÖğrenci ID veya TC No girin (çıkmak için 'q'): ").strip()
        
        if girilen_no.lower() == 'q':
            print("Program sonlandırıldı.")
            break
        
        yuz_kaydet(girilen_no)
        
        devam = input("\nBaşka öğrenci kaydedecek misiniz? (e/h): ").strip().lower()
        if devam != 'e':
            print("Program sonlandırıldı.")
            break

if __name__ == "__main__":
    main()