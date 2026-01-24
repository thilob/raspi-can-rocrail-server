```md
# raspi-can-rocrail-server
Scripts for easily setting up a Raspberry Pi with a CAN interface and Rocrail

On this page I describe how a freshly installed Raspberry Pi can be equipped with Rocrail and, by using a CAN HAT, also be used as a CAN interface for Rocrail.

## Initial situation
The Raspberry Pi has been freshly installed using Raspberry Pi OS in 64-bit, Lite configuration.

As the CAN HAT I am using a **“Waveshare 2-Channel Isolated CAN Expansion HAT for Raspberry Pi, Dual Chips Solution”** (2-CH CAN HAT).  
The HAT can be mounted right at the beginning.

## Update first, please!
- After the fresh installation, the Raspberry Pi should be brought up to date with  
  <code>sudo apt update && sudo apt upgrade</code>.
- If you like, you can then flash the EEPROM to the latest version with  
  <code>sudo rpi-update</code>.
- Afterwards, reboot the Raspberry Pi with  
  <code>sudo reboot</code>.

## My setup
I come from a time when the Märklin 6021 control unit was “the hot stuff”. I am still perfectly happy with it.  
However, as someone who has been working in IT for more than three decades, I have repeatedly asked myself how something like an “electronic signal box” could be realized.

The various Control Stations or other great products from competitors were priced beyond the hobby budget, so the next step was a **Mobile Station 2 with Gleisbox 61116**. That made things a bit more modern.

Compared to the “old digital days”, the rather cumbersome task of searching for the correct turnouts to switch on the MS2 revived the idea of an “electronic signal box” again—especially after I found out that Märklin apparently uses a CAN bus.

### Excursion: the CAN bus
The term is probably familiar to anyone who has dealt more closely with automotive technology. This bus system is well known for being installed in virtually every car and truck, where it connects control units, sensors, and actuators (i.e. things where something actually happens).

Unlike a computer network (“LAN”), packets are not sent directly from one point to another. Instead, each message is—simplified—prefixed with a type identifier (“left turn signal”, “right turn signal”, “message from the speed sensor”, “message from the catalytic converter”) and then put on the bus.

All devices are connected to the bus and listen to everything, filtering out the information relevant to them. If the information concerns them, they briefly acknowledge it on the bus so the sender knows that someone was able to use the message.

The CAN bus usually consists of two wires and, as a third reference potential, ground (GND).

The two wires carry a differential signal, which makes the system very robust overall.

Roughly speaking, you can imagine the differential signal as a square wave and its mirrored counterpart with opposite polarity, something like this:

<code>
     |------|    |------|                  |-----|       |-----|
-----|      |----|      |------------------|     |-------|     |---------------
=======================(imaginary mirror)=====================================
-----|      |----|      |------------------|     |-------|     |---------------
     |------|    |------|                  |-----|       |-----|
</code>

So if an error occurs on the upper wire (high signal), it can be detected by comparing it with the lower wire (low signal).

The key to robustness, however, is that the imaginary mirror is not at “0 volts” but slightly above it, namely at +2.5 volts.

With this offset:
- A digital “1” on the high line corresponds to +3.5 V, and a digital “0” to +2.5 V.
- On the low line, a digital “1” is at +2.5 V and a digital “0” at +1.5 V.

This offset has several advantages:
- When probing a CAN bus, neither of the two lines should be at 0 volts. If they are, something is wrong—usually the bus line is interrupted.
- If you measure a value greater than +2.5 V on a line, it is definitely the high line.
- If you measure a value between +1.5 V and +2.5 V, it is the low line.
- High and low lines must not be swapped in a CAN system; otherwise, the comparator circuits in the CAN bus components will no longer recognize a valid signal.

Thanks to this technique and the usually twisted pair wiring, the CAN bus is robust against interference such as mobile radio signals or strong electric motors.

In the automotive sector, CAN can reach quite high speeds (1 Mbit/s). In the Märklin system, however, only a quarter of that speed is used.

The “MBUS” therefore runs at **250 kbit/s**, which is important later when configuring the Raspberry Pi.

## The CAN HAT
I deliberately chose a somewhat more expensive but **galvanically isolated** CAN HAT. Why?

The Raspberry Pi and CAN HAT do not necessarily have to be connected to the same power outlet as the model railway transformer. In theory, different potentials and thus leakage currents could occur, potentially damaging either the model railway control or the computer.

Isolation is usually achieved using optocouplers. These are small packages containing, on one side, connections to an LED. Depending on whether a “0” or “1” is present, the LED is off or on.

On the other side of the package is a light-sensitive element. It “sees” when the LED is on and then outputs a “1” to the computer; otherwise, it outputs a “0”.

The CAN HAT is integrated into the Raspberry Pi system much like a serial interface or a network interface.

I would also like to mention the concept of **termination**. For stable bus operation (and to generate the correct voltages), termination resistors are provided at the ends of the bus. In most cases, these are already set correctly from the factory.

In addition, some CAN HATs have jumpers for different operating voltages. Please note that the Raspberry Pi GPIO pins usually operate at **3.3 V**.

## Preparing the Raspberry Pi for the CAN HAT

### Settings in the configuration menu
By running <code>raspi-config</code> you enter the Raspberry Pi configuration program.

The following settings are changed:
- (If required) **System Options → Hostname**: the device name of the Raspberry Pi. If you operate multiple devices in your network, they must all have different names.
- **Interface Options → SPI**: enable it. The “Serial Peripheral Interface” is the communication interface between the Raspberry Pi and the CAN HAT. Data is transferred via these lines.
- **Advanced Options → WLAN Power Save**: disable it. Especially if you later want to send or receive commands or status messages via WLAN, you should disable power saving; otherwise, the Raspberry Pi might miss messages.

Afterwards, please reboot the Raspberry Pi once. You can then reach the device under its new hostname.

### The script for automatic system configuration
Technically, the Device Tree overlays must be adjusted and kernel modules loaded on the Raspberry Pi.

For many people this feels like “magic”. Therefore, I had a script created via *vibe coding* to handle this.

Vibe coding describes the activity of telling an AI (via prompts) what it should do. It’s a pretty cool technique. If you know how something works and what should happen in the end, you can describe this to the AI and it will create the “program” for it. In the past, this required much more typing and debugging…

In short, the following steps are performed by the script:
- The Raspberry Pi is told which pins to use and at what speed it should communicate with the CAN HAT at the hardware level.
- Then the Raspberry Pi kernel is told how to communicate with the HAT at the software level.
- The CAN bus is then represented on the Raspberry Pi system side so that it behaves like a network interface.
- In the final step, the software package **can-utils** is installed. This allows us to read from and write to the CAN bus via the command line.

To ensure that nothing is broken if the script is run multiple times, it checks at each step whether the change has already been applied (idempotency).

#### Running the script for automatic system configuration
The script <code>setup-can.sh</code> can be found here on GitHub.

To make it executable, set the execute bit:

<code>chmod +x setup_can.sh</code>

Then run the script with root (“admin”) privileges:

<code>sudo ./setup_can_marklin.sh</code>

#### Health check
The script <code>can-health-check.sh</code> then checks the various CAN bus parameters.

Again, make it executable:

<code>chmod +x setup_can.sh</code>

Then run it with root privileges:

<code>sudo ./can-health-check.sh</code>

With CAN HATs that have multiple buses, it can also happen that the bus names are swapped (can0 / can1). Therefore, feel free to try the health check with both options, can0 and can1.

In my case, a Gleisbox is connected. It sends individual CAN frames—even in stop mode! This then looks like:

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

If you see these frames, you’ve already overcome the hardest part.

---

## Installing Rocrail

The software can be downloaded from  
https://www.rocrail.online/rocrail-snapshot/index.php

Since we are using the 64-bit version of Raspberry Pi OS, we also need the 64-bit version (“ARM64”) of Rocrail for Raspberry Pi.  
The file name is usually: <code>Rocrail-PiOS11-ARM64.zip</code>

With the following commands, the current package is downloaded and unpacked into the “Rocrail” subdirectory:

<code>
wget https://www.rocrail.online/rocrail-snapshot/Rocrail-PiOS11-ARM64.zip
unzip Rocrail-PiOS11-ARM64.zip -d Rocrail
cd Rocrail
</code>

With a confident <code>./startrocrail.sh</code>, Rocrail should start on the Raspberry Pi.  
You can now start Rocview on another computer in the WLAN and connect to Rocrail by specifying the Raspberry Pi’s hostname (“Connect to”).

---

**Rocrail is open source! And open source should also be “worth something” to you!**
- [x] You like Rocrail/Rocview?
- [x] Several people have invested their free time to develop this software!
- [x] The software continues to be developed. People continue to invest their time. **FOR YOU!**
- [x] Be fair! Support the developers and purchase a [Support Key!](https://wiki.rocrail.net/doku.php?id=supportkey-en#commercial_support_key)
- [x] In return, you can use the Pro version of Rocrail with the Support Key. The advantages are also listed on the website.

---

## Where is the journey heading next?

I will not explain the configuration of Rocrail here—others can do that better. But the “electronic signal box” is now possible. And much, much more!

I am particularly interested in two things:

- **Block operation with Rocrail**: I want to use light barriers to detect when a train enters or leaves a certain section. This allows automated operation. For this, I want to connect IR light barriers to an ESP32, which then sends status messages to the Rocrail control center via WLAN using the UDP protocol. And maybe the reverse direction will also work, allowing commands to be sent to the ESP32—for example, to control light signals.
- **Development of a DCC decoder**: If the path via ESP32 turns out to be unreliable, an ESP32 can also be programmed as a DCC decoder. This would allow things like light signals, (building) lighting, functional models, or a turntable to be digitalized. Old turntables can be found for under 100 euros; new ones cost many times more—not to mention transfer tables.

More on this once concrete plans exist.

Kind regards,  
Thilo
```
