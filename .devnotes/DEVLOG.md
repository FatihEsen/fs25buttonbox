# FSTel (Farming Simulator 25 Telemetry & Control Terminal)
## Geliştirme Günlüğü ve Durum Takibi

### 📌 Bileşenler ve Mimari
1. **`mod/FS25_FSTel/`**: FS25 GIANTS Engine 10 Lua Modu.
   - Araç (Vehicle), motor, şanzıman, aydınlatma, yakıt ve bağlı tüm ekipmanların (Implements, FillUnits, Pipe, Foldable, Attachable) verilerini toplar.
   - `socket.udp()` üzerinden yerel porta (Varsayılan UDP `127.0.0.1:41234`) JSON formatında ~30Hz hızında veri akışı sağlar.
   - `pcall` korumalı hata yönetimi ile oyunun çökmesini veya performans düşüşünü engeller.
   - `mod/package_mod.ps1` scripti ile doğrudan `D:\Documents\My Games\FarmingSimulator2025\mods\FS25_FSTel.zip` konumuna paketlenip kurulabilir.

2. **`server/`**: Node.js PC Köprüsü (Bridge).
   - UDP Telemetri Dinleyicisi (`127.0.0.1:41234`).
   - WebSocket Dağıtıcısı (`0.0.0.0:8080`) -> Android ve Web istemcilerine canlı veri yayını.
   - UDP Zero-Config Keşif Yayını (LAN Beacon: `41235`) -> Android uygulamasının IP girmeden otomatik bağlanması.
   - Girdi Emülasyonu (Sanal Buton Basışları -> FS25 Tuş Atamaları / Windows SendInput).
   - Dahili Demo Simülatörü: FS25 açık değilken arayüzün dinamik olarak test edilmesini sağlar.
   - Web İstemcisi Barındırma (HTTP Static Server Port: `3000`).

3. **`web/`**: Modern Web İstemcisi (Tamamlandı).
   - ISOBUS / VarioTerminal tarzı Koyu & Rugged arayüz (`web/style.css`).
   - Dokunsal 3D butonlar, canlı SMD LED geri bildirimleri, SVG hız kadranı, RPM ve motor yükü barları.
   - Çift yönlü WebSocket köprüsü (`web/app.js`), Web Audio API ile düşük gecikmeli tıklama sesi ve mobil dokunmatik haptic titreşim.
   - 4 farklı sekme: Hızlı Kontroller & Göstergeler, 4x4 Tam Buton Kutusu Matrisi, Ekipman & Tank Derinlemesine İzleme, Ayarlar & Demo Kontrolü.

4. **`android/`**: Android Tablet & Telefon İstemcisi (Sırada).
   - Kotlin + Jetpack Compose + Material 3.
   - UDP Auto-Discovery, WebSocket client, StateFlow mimarisi.
   - Gelişmiş Haptic Feedback (Motor yükü, devir, vites ve buton basış titreşimleri).

### 🚀 Git Senkronizasyonu
- GitHub Remote: `https://github.com/FatihEsen/fs25buttonbox.git`
- Branch: `main` (Senkronize edildi ve güncel).
