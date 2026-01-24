# raspi-can-rocrail-server
Skripte zum leichen Aufsetzen eines Raspi mit CAN-Interface und Rocrail

Auf dieser Seite beschreibe ich, wie ein frisch aufgesetzter Raspberry Pi mit Rocrail ausgestattet und durch Nutzung eines CAN-Hat auch zum CAN-Interface für Rocrail wird.

## Ausgangslage:
Der Raspi ist frisch installiert worden, dabei wurde RaspiOS in 64bit in der Lite-Konfiguration benutzt. 
Als CAN-Hat verwende ich ein "Waveshare 2-Channel Isolated CAN Expansion HAT for Raspberry Pi, Dual Chips Solution" (2-CH CAN HAT). Das Hat kann direkt zu Beginn montiert werden.

## Update, bitte!
- nach der Neuinstallation sollte der Raspi mit <code>sudo apt update && sudo apt upgrade</code> auf den neuesten Softwarestand gebracht werden.
- wer mag, kann anschließend mit <code>sudo rpi-update</code> das Eprom auf den aktuellen Stand flashen.
- anschließend wird der Raspi mit <code>sudo reboot</code> neu gestartet.

## Mein Setup
Ich komme aus einer Zeit, in der die Märklin 6021-Zentrale "der heiße Scheiß" war. Damit bin ich auch immer noch glücklich. Als einer, der aber seit gut drei Jahrzehnten im IT-Bereich unterwegs ist, habe ich mir aber schon hin und wieder die Frage gestellt, wie man denn so etwas wie ein "elektronisches Stellwerk" bekommen kann. Die verschiedenen Control Station oder andere, tolle Produkte von Mitbewerbern waren preislich außerhalb des Hobby-Budgets, so dass ich mich im nächsten Schritt zu einer Mobile Station 2 durchgerungen habe. Damit war ich vorerst einen Schritt moderner.

Das -im Vergleich zur "alten Digitalzeit" aufwändige Suchen der umzuschaltenden Weichen in der MS2 hat dann aber wieder die Idee eines "elektronischen Stellwerks" geweckt. Ganz besonders, nachdem ich herausgefunden habe, dass Märklin offenbar einen CAN-Bus einsetzt. 

### Der CAN-Bus
Den Begriff hat wahrscheinlich jeder schon mal gehört, der sich etwas intensiver mit KFZ-Technik beschäftigt hat. Bekannt ist dieses Bussystem dafür, dass es praktisch in jedem PKW und LKW eingebaut wird und dort Steuergeräte, Sensoren und Aktoren (also irgendwas, an dem etwas passiert) miteinander verbindet.

Im Gegensatz zu einem Computer-Netzwerk ("LAN") werden Pakete aber nicht zielgerichtet von einer Stelle zur anderen geschickt. Sondern jeder Nachricht wird, vereinfacht gesagt, eine Typenkennung vorangestellt ("betrifft Blinker links", "betrifft Blinker rechts", "Nachricht vom Geschwindigkeitssensor", "Nachricht vom Kat") und auf den Bus geschickt. 

Alle Geräte hängen an dem Bus und hören alles mit, und "filtern" sich die für sie notwendigen Informationen raus. Wenn die Information sie betraf, geben sie kurz eine Quittung auf den Bus und der Sender weiß dann, dass irgendjemand seine Nachricht gebrauchen konnte. 

Der CAN-Bus besteht normalerweise aus zwei Drähten und als drittem Potention der "Masse" (GND). Die beiden Drähte übertragen ein Differentialsignal, was das System insgesamt sehr robust macht.
Das Differentialsignal muss man sich grob vorstellen wie ein Rechtecksignal und das dazu passende Spiegelbild in genau die andere "Polung". Also ungefähr so:

<code>
     |------|    |------|                  |-----|       |-----|
-----|      |----|      |------------------|     |-------|     |---------------
======================(Imaginärer Spiegel)=====================================
-----|      |----|      |------------------|     |-------|     |---------------
     |------|    |------|                  |-----|       |-----|
</code>


Sollte also auf der oberen Leitung (High-Signal) ein Fehler auftreten, könnte man es durch Vergleich mit der unteren Leitung (Low-Signal) also feststellen.
Der Schlüssel zur Robustheit ist allerdings, dass der imaginäre Spiegel nicht bei "0 Volt" liegt, sondern etwas darüber, nämlich bei +2,5 Volt. 
Mit diesem Versatz bedeutet eine digitale "1" auf der High-Leitung dann eine Spannung von +3,5V und eine digitale "0" dann +2,5V.
Auf der Low-Leitung liegt die digitale "1" dann auch bei +2,5V und die digitale "0" bei +1,5V.

Dieser Versatz hat also mehrere Vorteile:
- Testet man einen CAN-Bus durch, darf auf keiner der beiden Leitungen 0 Volt anliegen. Dann ist etwas verkehrt - in der Regel ist dann die Busleitung unterbrochen.
- Wenn man auf der Leitung einen Wert >+2,5V wahrnimmt, handelt es sich definitiv um die High-Leitung.
- Wenn man auf der Leitung einen Wert zwischen +1,5V und +2,5V wahrnimmt, handelt es sich um die Low-Leitung.
- High- und Low-Leitungen darf man im CAN-System demnach auch nicht vertauschen. Dann nehmen die Vergleicher-Bausteine in den CAN-Buselementen kein gültiges Signal mehr wahr.

Durch diese Technik und die üblicherweise miteinander verdrillten Leitungen ist der CAN-Bus auch recht robust gegen einstrahlende Signale wie Mobilfunk oder auch starke Elektromotoren.

Der CAN-Bus kann im Automotive-Bereich auch rech hohe Geschwindigkeiten verarbeiten (1 MBit pro Sekunden). Im Märklin-System wird allerdings nur ein viertel der Geschwindigkeit verwendet. 

Der "MBUS" läuft also mit 250kBit/s. Das ist hinterher wichtig für die Parametrierung des Raspberry.


