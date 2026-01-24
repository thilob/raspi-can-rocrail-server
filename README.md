**<a>🇩🇪 Deutsche Version</a>** | **<a href="README.en.md">🇬🇧 English version</a>**

# raspi-can-rocrail-server
Skripte zum leichten Aufsetzen eines Raspi mit CAN-Interface und Rocrail

Auf dieser Seite beschreibe ich, wie ein frisch aufgesetzter Raspberry Pi mit Rocrail ausgestattet und durch Nutzung eines CAN-Hat auch zum CAN-Interface für Rocrail wird.

## Ausgangslage:
Der Raspi ist frisch installiert worden, dabei wurde RaspiOS in 64bit in der Lite-Konfiguration benutzt. 

Als CAN-Hat verwende ich ein "Waveshare 2-Channel Isolated CAN Expansion HAT for Raspberry Pi, Dual Chips Solution" (2-CH CAN HAT). Das Hat kann direkt zu Beginn montiert werden.

## Update, bitte!
- nach der Neuinstallation sollte der Raspi mit <code>sudo apt update && sudo apt upgrade</code> auf den neuesten Softwarestand gebracht werden.
- wer mag, kann anschließend mit <code>sudo rpi-update</code> das Eprom auf den aktuellen Stand flashen.
- anschließend wird der Raspi mit <code>sudo reboot</code> neu gestartet.

## Mein Setup
Ich komme aus einer Zeit, in der die Märklin 6021-Zentrale "der heiße Scheiß" war. Damit bin ich auch immer noch glücklich. Als einer, der aber seit gut drei Jahrzehnten im IT-Bereich unterwegs ist, habe ich mir schon hin und wieder die Frage gestellt, wie man denn so etwas wie ein "elektronisches Stellwerk" hinbekommen kann. Die verschiedenen Control Station oder andere, tolle Produkte von Mitbewerbern waren preislich außerhalb des Hobby-Budgets, so dass ich mich im nächsten Schritt zu einer Mobile Station 2 mit Gleisbox 61116 durchgerungen habe. Damit war ich vorerst einen Schritt moderner.

Das -im Vergleich zur "alten Digitalzeit"- aufwändige Suchen der umzuschaltenden Weichen in der MS2 hat dann aber wieder die Idee eines "elektronischen Stellwerks" geweckt. Ganz besonders, nachdem ich herausgefunden habe, dass Märklin offenbar einen CAN-Bus einsetzt. 

### Exkurs zum CAN-Bus
Den Begriff hat wahrscheinlich jeder schon mal gehört, der sich etwas intensiver mit KFZ-Technik beschäftigt hat. Bekannt ist dieses Bussystem dafür, dass es praktisch in jedem PKW und LKW eingebaut wird und dort Steuergeräte, Sensoren und Aktoren (also irgendwas, an dem etwas passiert) miteinander verbindet.

Im Gegensatz zu einem Computer-Netzwerk ("LAN") werden Pakete aber nicht zielgerichtet von einer Stelle zur anderen geschickt. Sondern jeder Nachricht wird, vereinfacht gesagt, eine Typenkennung vorangestellt ("betrifft Blinker links", "betrifft Blinker rechts", "Nachricht vom Geschwindigkeitssensor", "Nachricht vom Kat") und auf den Bus geschickt. 

Alle Geräte hängen an dem Bus und hören alles mit, und "filtern" sich die für sie notwendigen Informationen raus. Wenn die Information sie betraf, geben sie kurz eine Quittung auf den Bus und der Sender weiß dann, dass irgendjemand seine Nachricht gebrauchen konnte. 

Der CAN-Bus besteht normalerweise aus zwei Drähten und als drittem Potential der "Masse" (GND). 

Die beiden Drähte übertragen ein Differentialsignal, was das System insgesamt sehr robust macht.

Das Differentialsignal muss man sich grob vorstellen wie ein Rechtecksignal und das dazu passende Spiegelbild in genau die andere "Polung". Also ungefähr so:

<code>
     |------|    |------|                  |-----|       |-----|
-----|      |----|      |------------------|     |-------|     |---------------
======================(Imaginärer Spiegel)=====================================
-----|      |----|      |------------------|     |-------|     |---------------
     |------|    |------|                  |-----|       |-----|
</code>


Sollte also auf der oberen Leitung (High-Signal) ein Fehler auftreten, könnte man es durch Vergleich mit der unteren Leitung (Low-Signal) feststellen.

Der Schlüssel zur Robustheit ist allerdings, dass der imaginäre Spiegel nicht bei "0 Volt" liegt, sondern etwas darüber, nämlich bei +2,5 Volt. 

Mit diesem Versatz bedeutet eine digitale "1" auf der High-Leitung dann eine Spannung von +3,5V und eine digitale "0" dann +2,5V.

Auf der Low-Leitung liegt die digitale "1" dann auch bei +2,5V und die digitale "0" bei +1,5V.

Dieser Versatz hat mehrere Vorteile:
- Testet man einen CAN-Bus durch, darf auf keiner der beiden Leitungen 0 Volt anliegen. Dann ist etwas verkehrt - in der Regel ist dann die Busleitung unterbrochen.
- Wenn man auf der Leitung einen Wert >+2,5V wahrnimmt, handelt es sich definitiv um die High-Leitung.
- Wenn man auf der Leitung einen Wert zwischen +1,5V und +2,5V wahrnimmt, handelt es sich um die Low-Leitung.
- High- und Low-Leitungen darf man im CAN-System nicht vertauschen. Dann erkennen die Vergleicher-Bausteine in den CAN-Buselementen kein gültiges Signal mehr.

Durch diese Technik und die üblicherweise miteinander verdrillten Leitungen ist der CAN-Bus robust gegen einstrahlende Signale wie Mobilfunk oder auch starke Elektromotoren.

Der CAN-Bus erreicht im Automotive-Bereich recht hohe Geschwindigkeiten (1 MBit pro Sekunden). Im Märklin-System wird allerdings nur ein Viertel der Geschwindigkeit verwendet. 

Der "MBUS" läuft also mit 250kBit/s. Das ist hinterher wichtig für die Parametrierung des Raspberry.

## DAS CAN-Hat
Ich habe mich bewusst zu einem etwas teureren, dafür aber galvanisch isoliertem CAN-Hat entschieden. Warum? 

Der Raspberry samt CAN-Hat muss ja nicht unbedingt an der gleichen Steckdose hängen wie der Trafo der Modellbahn. Theoretisch könnten also andere Potentiale und damit "Kriechströme" auftreten, die entweder die Modellbahnsteuerung oder den Computer beschädigen.

Die Trennung wird in der Regel durch Optokoppler erreicht. Das sind kleine Gehäuse, in denen auf der einen Seite Anschlüsse zu einer LED gehen. Je nach "0" oder "1" geht die dann an oder aus.

In der anderen Seite des Gehäuses ist ein lichtempfindliches Element eingebaut. Es "sieht", wenn die Diode an ist, und gibt dann eine "1" zum Computer aus. Ansonsten einen "0".

Das CAN-Hat wird im Raspi so in das System eingebunden wie z.B. eine serielle Schnittstelle oder eine Netzwerkschnittstelle.

Erwähnen möchte ich noch den Begriff der "Terminierung". Damit der Bus stabil läuft (und die verschiedenen Spannungen sauber erzeugt werden können), sind an den Busenden Abschlusswiderstände vorgesehen. In der Regel sind die im Auslieferungszustand schon richtig gesetzt.

Außerdem haben manche CAN-Hats Jumper für verschiedene Betriebsspannungen. Beachtet, dass der Raspberry an den GPIO-Pins üblicherweise mit 3,3V betrieben wird.

## Raspi für das CAN-Hat vorbereiten

### Einstellungen im Konfigurationsmenü

Durch Aufrufen von <code>raspi-config</code> gelangt man in das Konfigurationsprogramm des Raspberry.

Dort wird geändert:
- (bei Bedarf) System Options -> Hostname: der Gerätename des Raspberry. Betreibt man mehrere in seinem Netzwerk, müssen alle unterschiedliche Namen haben.
- Interface Options -> SPI: einschalten. Das "Serial Peripheral Interface" bildet die Kommunikationsschnittstelle zwischen Raspberry und dem CAN-Hat. Über diese Leitungen weden die Daten übertragen.
- Advanced Options -> WLAN Power Save: ausschalten. Gerade wenn man später über WLAN Kommandos oder Zustände senden oder empfangen will, sollte man den Stromsparmodus ausschalten. Sonst könnte der Raspberry die ein oder andere Nachricht verpassen.

Anschließend bitte den Raspberry einmal neu booten. Danach kann man das Gerät auch unter dem neuen Hostnamen erreichen.

### Das Skript für die automatische Systemkonfiguration
Technisch müssen nun auf dem Raspberry das Device-Tree Overlay angepasst werden und Kernelmodule geladen werden.

Für viele Leute ist das "Magie". Deshalb habe ich per AI-assisted Coding dafür ein Skript erstellen lassen.

AI-assisted Coding beschreibt die Tätigkeit, bei der man einer KI "sagt" (prompted), was sie machen soll. Eine recht coole Technik. Wenn man weiß, wie etwas funktioniert und was hinterher passieren soll, kann man das der KI mitteilen und die erstellt dann das "Programm" dazu. Früher war das sehr viel Tipparbeit und Fehlersucherei......

In Kurzform passieren in dem folgenden Skript diese Schritte:
- Dem Raspberry wird gesagt, an welchen Anschlüssen er mit welcher Geschwindigkeit mit dem CAN-Hat hardwareseitig reden muss.
- Dann wird dem Raspberry-Kernel gesagt, wie es mit dem Hat softwareseitig reden muss
- dann wird der CAN-Bus auf dem Raspberry systemseitig so nachgebildet, dass er sich wie ein Netzwerkanschluss verhält.
- im letzten Schritt wird das Softwarepaket "can-utils" installiert. Damit können wir per Kommandozeile auf dem CAN-Bus mitlesen und auch schreiben.

Damit nichts zerstört wird, wenn man das Skript mehrfach ausführt, prüft es bei jedem Schritt ob die Änderung nicht schon durchgeführt wurde (Idempotenz).

#### Aufruf des Skriptes für die automatische Systemkonfiguration

Das Skript <code>setup-can.sh</code> findet ihr hier im Github.

Um es ausführbar ("startbar") zu machen, muss das Execute-Bit gesetzt werden:

<code>chmod +x setup-can.sh</code>

Anschließend muss das Skript mit Root-Rechten ("Admin-Rechten") gestartet werden:

<code>sudo ./setup-can.sh</code>

#### Health-Check

Das Skript <code>can-health-check.sh</code> überprüft anschließend die verschiedenen Parameter des CAN-Bus.

Auch hier wieder: ausführbar machen:

<code>chmod +x can-health-check.sh</code>

Anschließend muss das Skript mit Root-Rechten ("Admin-Rechten") gestartet werden:

<code>sudo ./can-health-check.sh</code>

Bei CAN-Hats mit mehreren Bussen kann es auch vorkommen, dass die Busnamen vertauscht sind (can0 / can1). Deshalb den Health-Check ruhig auch mit den Optionen can0 und can1 ausprobieren.

In meinem Fall hängt eine Gleisbox dran. Die sendet -auch im Stop-Betrieb!- einzelne CAN-Frames. Das sieht dann so aus:

<code>
  can1  0030532D   [0] 
  can1  00314F73   [8]  47 47 34 08 01 44 00 10
  can1  0030532D   [0] 
  can1  00314F73   [8]  47 47 34 08 01 44 00 10
  can1  0030532D   [0] 
  can1  00314F73   [8]  47 47 34 08 01 44 00 10
  can1  0030532D   [0] 
  can1  00314F73   [8]  47 47 34 08 01 44 00 10
  can1  0030532D   [0] 
  can1  00314F73   [8]  47 47 34 08 01 44 00 10
  can1  0008532D   [6]  00 00 40 06 02 CA
</code>

Wenn diese Frames angezeigt werden, habt ihr das Schwerste hinter euch. 

---

## Installation von Rocrail

Die Software kann unter https://www.rocrail.online/rocrail-snapshot/index.php heruntergeladen werden.

Da wir die 64bit-Version von PiOS nutzen, müssen wir auch die 64bit-Version ("ARM64") von Rocrail für Raspberry Pi herunterladen.
Üblicherweise lautet der Dateiname:  <code>Rocrail-PiOS11-ARM64.zip</code>

Mit diesem Befehl wird das aktuelle Paket heruntergeladen und in das Unterverzeichnis "Rocrail" entpackt:
<code>
wget https://www.rocrail.online/rocrail-snapshot/Rocrail-PiOS11-ARM64.zip
unzip Rocrail-PiOS11-ARM64.zip -d Rocrail
cd Rocrail
</code>

Mit einem beherzten <code>./startrocrail.sh</code> sollte Rocrail auf dem Raspberry starten.
Ihr könnt nun Rocview auf einem weiteren Rechner im WLAN starten und euch unter Angabe des Hostnamens des Raspberry mit Rocrail verbinden ("Connect to").

---

**Rocrail ist Opensource! Und Opensource sollte euch auch "etwas wert sein"!**
- [x] euch gefällt Rocrail/Rocview?
- [x] mehrere Leute haben dafür ihre Freizeit geopfert und die Software programmiert!
- [x] die Software wird weiterentwickelt. Die Leute opfern weiterhin ihre Zeit. **FÜR EUCH!**
- [x] Seid fair! Unterstützt die Programmierer und erwerbt einen [Support Key!](https://wiki.rocrail.net/doku.php?id=supportkey-en#commercial_support_key)
- [x] Im Gegenzug nutzt ihr mit dem Support Key die Pro-Version von Rocrail. Die Vorteile findet ihr auch auf der Seite.

---

## Wo geht die Reise als nächstes hin?

Ich werde hier nicht die Konfiguration von Rocrail erklären. Das können andere besser. Aber: Das "elektronische Stellwerk" ist damit möglich. Und noch viel, viel mehr!
Ich habe großes Interesse an zwei Dingen:

- **Blockbetrieb** mit Rocrail: Ich möchte über Lichtschranken feststellen, wenn ein Zug in einen bestimmten Bereich hereinfährt oder ihn wieder verlässt. So kann ein automatischer Betrieb durchgeführt werden. Dafür will ich IR-Lichtschranken an einen ESP32 anschließen, welcher über das UDP-Protokoll per WLAN Zustandsmeldungen an die Rocrail-Zentrale sendet. Und vielleicht funktioniert ja auch der umgekrhte Weg und man kann dem ESP32 Befehle senden. So könnten zum Beispiel recht einfach Lichtsignale angesteuert werden.
- **Entwicklung eines DCC-Dekoders**: Wenn der Weg zum ESP32 unzuverlässig ist, kann ein ESP32 aber als DCC-Dekoder programmiert werden. So könnten Dinge wie Lichtsignale, (Haus-)Beleuchtung, Funktionsmodelle oder eine Drehscheibe digitalisiert werden. Alte Drehscheiben bekommt man für unter 100 Euro. Neue kosten ein vielfaches - von Schiebebühnen ganz zu schweigen.

Mehr an dieser Stelle, sobald es konkrete Planungen gibt.


Viele Grüße,
Thilo
