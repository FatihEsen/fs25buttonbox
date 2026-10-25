# FSTel (Farming Simulator 25 Telemetry & Control Terminal)
## Geliştirme Günlüğü ve Durum Takibi

### 📌 Bileşenler ve Mimari
1. **`mod/FS25_FSTel/`**: FS25 GIANTS Engine 10 Lua Modu.
   - Araç (Vehicle), motor, şanzıman, aydınlatma, yakıt ve bağlı tüm ekipmanların (Implements, FillUnits, Pipe, Foldable, Attachable) verilerini toplar.
   - `socket.udp()` üzerinden yerel porta (Varsayılan UDP `127.0.0.1:41234`) JSON formatında ~20-30Hz hızında veri akışı sağlar.
   - `pcall` korumalı hata yönetimi ile oyunun çökmesini veya performans düşüşünü engeller.

2. **`server/`**: Node.js PC Köprüsü (Bridge).
   - UDP Telemetri Dinleyicisi (`127.0.0.1:41234`).
   - WebSocket Dağıtıcısı (`0.0.0.0:8080`) -> Android ve Web istemcilerine canlı veri yayını.
   - UDP Zero-Config Keşif Yayını (LAN Beacon: `41235`) -> Android uygulamasının IP girmeden otomatik bağlanması.
   - Girdi Emülasyonu (Sanal Buton Basışları -> FS25 Tuş Atamaları / Windows SendInput).
   - Web İstemcisi Barındırma (HTTP Static Server).

3. **`web/`**: Modern Web İstemcisi.
   - ISOBUS / VarioTerminal tarzı Koyu & Rugged arayüz.
   - Vanilla CSS, responsive layout, SVG ve Canvas göstergeler.
   - Çift yönlü WebSocket, otomatik yeniden bağlanma, ses/titreşim geri bildirimi.

4. **`android/`**: Android Tablet & Telefon İstemcisi.
   - Kotlin + Jetpack Compose + Material 3.
   - UDP Auto-Discovery, WebSocket client, StateFlow mimarisi.
   - Gelişmiş Haptic Feedback (Motor yükü, devir, vites ve buton basış titreşimleri).
