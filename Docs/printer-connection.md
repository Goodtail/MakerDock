# Printer connection

Open **Settings → Printer connection**. Keep the Mac and printer on the same local network. Enter the printer's private IPv4 address, serial number (SN), and LAN access code, then choose **Save and test connection**. The code is the printer's local access code, not a Bambu account password. It is saved in macOS Keychain, separately for development and production. A blank code field reuses the saved code.

Find the IP in the printer's network settings, the SN in device information or Studio, and the code in LAN settings. MakerDock uses the public CA certificates in the separately installed official Bambu Studio to verify the printer certificate against the entered SN. Keep the Studio path in Settings current. It does not read Studio account credentials or load its networking plugin.

Try the existing network mode first. The X2D manual documents **Settings → LAN Only → Developer Mode**, but LAN Only disables cloud features including Handy and cloud print history. MakerDock never changes the printer's network mode. X2D firmware compatibility must be checked on the actual device; a successful mock-printer test is not a hardware certification.

## Link a live job to the queue

The queue shows a printer status card. Once a live report arrives, choose **Link this print to a queued model**, select the model, check its actual start time, and confirm. The app does not guess this association from a similar filename. A printer-supplied start timestamp or an existing queue start fills the date when available; otherwise the user must correct the proposed current time.

A bound job uses the printer's reported remaining time for queue planning. Paused, disconnected, stale, and completed-but-unrecorded jobs block later slots until their timing is known or the user records the result. It never starts the next print automatically.

A live transition to FINISH or FAILED captures the time the signal arrived. If the transition happened while disconnected, the received timestamp is explicitly marked for review rather than presented as the exact finish time. Recording remains a user action so the result, notes, and file moves can be checked. Failed work returns to waiting for a retry. No printer command is sent by these actions.

The completion form calculates elapsed time from start and end, including pauses. Both dates and duration remain editable. If a start was recorded, an estimate cannot overwrite elapsed time. With no start, the existing estimate prefill remains available.

Filament type and color observed while connected can fill the record. Grams remain empty: spool weight and spool remaining percentage are not the amount consumed by that print. Earlier colors used before connection may not have been observed. Historical Bambu cloud jobs are not imported.

## Transport and storage

The native Network.framework client uses MQTT 3.1.1 over TLS 1.2 or later on port 8883. It subscribes only to the exact `device/SERIAL/report` topic. Its outgoing packets are CONNECT, SUBSCRIBE, PINGREQ, and receipt acknowledgements; there is no PUBLISH or printer-command interface. Invalid certificates are rejected before the access code is sent. No wildcard topic, cloud login, or service-side account is needed for this local connection.

`printer-connection.json` contains the address, serial, and enabled flag. `printer-session.json` contains the current job's confirmed model association, timestamps, observed materials, and recorded flag. The code is never written into these files or application logs. Disconnect disables automatic reconnect; Forget removes the saved connection and Keychain code. Existing print history is preserved.

Reports are bounded to 1 MiB. Delta updates preserve fields from the same job, clear timing and filament metadata on a new job, and do not turn a zero remaining-time value into a completion event. Retained MQTT messages are ignored until live telemetry arrives. Network failures retry with backoff; credential, certificate, or unsupported-protocol failures remain visible for correction.

## Verification and references

Tests cover timestamp-based four-hour completion, persistence, job changes, pauses, stale remaining time, missed finish events, delta filament data, packet fragmentation, exact topics, and replay-safe recording. A local TLS mock printer verifies the native handshake, subscription, report receipt, QoS 1 acknowledgement, and wrong-serial certificate rejection before credentials.

- [Bambu X2D manual, pages 100–101](https://csm.bblcdn.com/hub/7c58718aaa2e40edab56efb87419a96a.pdf#page=101)
- [OpenBambuAPI report fields](https://github.com/Doridian/OpenBambuAPI/blob/main/mqtt.md)
- [OpenBambuAPI TLS verification notes](https://github.com/Doridian/OpenBambuAPI/blob/main/tls.md)
- [OASIS MQTT 3.1.1 specification](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html)

The transport is an independent implementation using Apple frameworks; no third-party MQTT library or Bambu networking plugin is bundled.
