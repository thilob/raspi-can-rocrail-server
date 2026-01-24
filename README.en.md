**<a href="README.md">🇩🇪 Deutsche Version</a>** | **<a>🇬🇧 English version</a>**

# raspi-can-rocrail-server
Scripts for easily setting up a Raspberry Pi with a CAN interface and Rocrail

On this page, I describe how a freshly installed Raspberry Pi can be equipped with Rocrail and, by using a CAN HAT, also becomes a CAN interface for Rocrail.

## Initial situation
The Raspberry Pi has been freshly installed using Raspberry Pi OS in 64-bit, Lite configuration.

As a CAN HAT, I am using a "Waveshare 2-Channel Isolated CAN Expansion HAT for Raspberry Pi, Dual Chips Solution" (2-CH CAN HAT). The HAT can be mounted right at the beginning.

## Update, please!
- After the fresh installation, the Raspberry Pi should be brought up to date with <code>sudo apt update && sudo apt upgrade</code>.
- If you like, you can then flash the EEPROM to the latest version with <code>sudo rpi-update</code>.
- Afterwards, reboot the Raspberry Pi with <code>sudo reboot</code>.

## My setup
I come from a time when the Märklin 6021 control unit was "the hot stuff". I am still perfectly happy with it. However, as someone who has been working in IT for more than three decades, I have repeatedly asked myself how something like an "electronic signal box" could be realized. The various Control Stations or other great products from competitors were priced beyond the hobby budget, so in the next step I opted for a Mobile Station 2 with track box 61116. That made things a bit more modern.

The rather cumbersome task—compared to the "old digital days"—of searching for the turnouts to switch on the MS2 revived the idea of an "electronic signal box" again, especially after I found out that Märklin apparently uses a CAN bus.

### Excursion: the CAN bus
The term is probably familiar to anyone who has dealt more closely with automotive technology. This bus system is well known for being installed in virtually every car and truck, where it connects control units, sensors, and actuators (i.e., devices where something actually happens).

Unlike a computer network ("LAN"), packets are not sent directly from one point to another. Instead, each message is—simplified—prefixed with a type identifier ("left turn signal", "right turn signal", "message from the speed sensor", "message from the catalytic converter") and then put on the bus.

All devices are connected to the bus and listen to everything, filtering out the information relevant to them. If the information concerns them, they briefly send an acknowledgment on the bus, and the sender then knows that someone was able to use the message.

The CAN bus normally consists of two wires and, as a third reference potential, ground (GND).

The two wires carry a differential signal, which makes the system very robust overall.

Roughly speaking, you can imagine the differential signal as a square wave and its mirrored counterpart with opposite polarity, something like this:

<code>
     |------|    |------|                  |-----|       |-----|
-----|      |----|      |------------------|     |-------|     |---------------
======================(imaginary mirror)=====================================
-----|      |----|      |------------------|     |-------|     |---------------
     |------|    |------|                  |-----|       |-----|
</code>


So if an error occurs on the upper wire (high signal), it can be detected by comparing it with the lower wire (low signal).

The key to robustness, however, is that the imaginary mirror is not at "0 volts" but slightly above it, namely at +2.5 volts.

With this offset, a digital "1" on the high wire then means a voltage of +3.5V and a digital "0" means +2.5V.

On the low wire, the digital "1" is then also at +2.5V and the digital "0" at +1.5V.

This offset has several advantages:
- If you test a CAN bus, neither of the two wires should be at 0 volts. If they are, something is wrong—usually the bus line is broken.
- If you detect a value >+2.5V on the wire, it is definitely the high wire.
- If you detect a value between +1.5V and +2.5V on the wire, it is the low wire.
- High and low wires must not be swapped in the CAN system. Otherwise, the comparator components in the CAN bus elements will no longer recognize a valid signal.

Due to this technology and the usually twisted wires, the CAN bus is robust against interfering signals such as mobile phones or strong electric motors.

The CAN bus achieves quite high speeds in the automotive sector (1 Mbit per second). In the Märklin system, however, only a quarter of the speed is used.

The "MBUS" therefore runs at 250 kbit/s. This is important later for configuring the Raspberry Pi.

## THE CAN HAT
I deliberately chose a somewhat more expensive but galvanically isolated CAN HAT. Why?

The Raspberry Pi with the CAN HAT does not necessarily have to be plugged into the same power outlet as the model railway transformer. In theory, different potentials and thus "leakage currents" could occur, which could damage either the model railway control or the computer.

The isolation is usually achieved by optocouplers. These are small packages where connections on one side go to an LED. Depending on "0" or "1", the LED turns on or off.

On the other side of the package, a light-sensitive element is built in. It "sees" when the diode is on and then outputs a "1" to the computer. Otherwise a "0".

The CAN HAT is integrated into the Raspberry Pi system like a serial interface or a network interface, for example.

I would also like to mention the term "termination". For the bus to run stably (and for the various voltages to be generated cleanly), termination resistors are provided at the bus ends. Usually, these are already set correctly in the delivery state.

In addition, some CAN HATs have jumpers for different operating voltages. Note that the Raspberry Pi usually operates at 3.3V on the GPIO pins.

## Preparing the Raspberry Pi for the CAN HAT

### Settings in the configuration menu

By calling <code>raspi-config</code>, you enter the Raspberry Pi's configuration program.

There, the following should be changed:
- (if needed) System Options -> Hostname: the device name of the Raspberry Pi. If you operate several in your network, they must all have different names.
- Interface Options -> SPI: enable. The "Serial Peripheral Interface" forms the communication interface between the Raspberry Pi and the CAN HAT. Data is transmitted via these lines.
- Advanced Options -> WLAN Power Save: disable. Especially if you later want to send or receive commands or states via WLAN, you should disable power saving mode. Otherwise, the Raspberry Pi might miss one or another message.

Afterwards, please reboot the Raspberry Pi once. After that, you can also reach the device under the new hostname.

### The script for automatic system configuration
Technically, the Device-Tree Overlay must now be adjusted on the Raspberry Pi and kernel modules must be loaded.

For many people, this is "magic". That's why I had a script created for this using AI-assisted Coding.

AI-assisted Coding describes the activity in which you "tell" (prompt) an AI what it should do. A pretty cool technique. If you know how something works and what should happen afterwards, you can tell the AI and it will then create the "program" for it. In the past, this was a lot of typing work and debugging......

In short, the following steps happen in the script:
- The Raspberry Pi is told at which connections and at what speed it should communicate with the CAN HAT on the hardware side.
- Then the Raspberry Pi kernel is told how to communicate with the HAT on the software side
- then the CAN bus is replicated on the Raspberry Pi system side so that it behaves like a network interface.
- in the last step, the "can-utils" software package is installed. This allows us to read and write on the CAN bus via the command line.

To ensure nothing is broken if you run the script multiple times, it checks at each step whether the change has not already been made (idempotence).

#### Calling the script for automatic system configuration

The script <code>setup-can.sh</code> can be found here on Github.

To make it executable ("startable"), the execute bit must be set:

<code>chmod +x setup-can.sh</code>

Then the script must be started with root privileges ("admin rights"):

<code>sudo ./setup-can.sh</code>

#### Health Check

The script <code>can-health-check.sh</code> then checks the various parameters of the CAN bus.

Again: make it executable:

<code>chmod +x can-health-check.sh</code>

Then the script must be started with root privileges ("admin rights"):

<code>sudo ./can-health-check.sh</code>

With CAN HATs that have multiple buses, it can also happen that the bus names are swapped (can0 / can1). Therefore, feel free to try the health check with the options can0 and can1 as well.

In my case, a track box is connected. It sends—even in stop mode!—individual CAN frames. This then looks like this:

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

If these frames are displayed, you have the hardest part behind you.

---

## Installing Rocrail

The software can be downloaded at https://www.rocrail.online/rocrail-snapshot/index.php.

Since we are using the 64-bit version of PiOS, we also need to download the 64-bit version ("ARM64") of Rocrail for Raspberry Pi.
The filename is usually: <code>Rocrail-PiOS11-ARM64.zip</code>

With this command, the current package is downloaded and extracted to the subdirectory "Rocrail":
<code>
wget https://www.rocrail.online/rocrail-snapshot/Rocrail-PiOS11-ARM64.zip
unzip Rocrail-PiOS11-ARM64.zip -d Rocrail
cd Rocrail
</code>

With a bold <code>./startrocrail.sh</code>, Rocrail should start on the Raspberry Pi.
You can now start Rocview on another computer on the WLAN and connect to Rocrail by specifying the hostname of the Raspberry Pi ("Connect to").

---

**Rocrail is open source! And open source should also "be worth something" to you!**
- [x] Do you like Rocrail/Rocview?
- [x] Several people have sacrificed their free time to program the software!
- [x] The software is being further developed. People continue to sacrifice their time. **FOR YOU!**
- [x] Be fair! Support the programmers and purchase a [Support Key!](https://wiki.rocrail.net/doku.php?id=supportkey-en#commercial_support_key)
- [x] In return, you can use the Pro version of Rocrail with the Support Key. You can also find the advantages on the page.

---

## Where is the journey going next?

I will not explain the configuration of Rocrail here. Others can do that better. But: The "electronic signal box" is now possible. And much, much more!
I am very interested in two things:

- **Block operation** with Rocrail: I want to use light barriers to detect when a train enters or leaves a certain area. This allows automatic operation. For this, I want to connect IR light barriers to an ESP32, which sends status messages to the Rocrail control center via the UDP protocol over WLAN. And perhaps the reverse way also works and you can send commands to the ESP32. This could make it quite easy to control light signals, for example.
- **Development of a DCC decoder**: If the path to the ESP32 is unreliable, an ESP32 can also be programmed as a DCC decoder. This could digitize things like light signals, (house) lighting, functional models, or a turntable. You can get old turntables for under 100 euros. New ones cost many times more—not to mention transfer tables.

More on this when there are concrete plans.


Best regards,
Thilo
