# ADR 0030: A scan page says why it has no camera picture

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

Scanning needs the camera. When the camera was refused, a scan page
("Scan ISBN barcode", "Scan a library QR", "Scan a library card") showed
its scan frame empty and stayed so: no word why, no way to the phone's
settings, no way to type the number instead. A phone without a camera
got the same page. And the cover camera answered every failure, a
refused camera too, with "Could not capture a photo.". The review of
November 2026 lists it as finding P4-M8.

What was read in the packages (at the versions the app is locked to),
tried outside git, and looked at on a phone with Android 14 BEFORE the
design was final (`PLAN.md`, D128):

- The scanner package (`flutter_zxing` 2.3.0) tells its host that the
  camera could not start only when the host passes a callback
  (`onControllerCreated`). Neither scan page passed it.
- It reports ONE kind of failure: the start of the camera throwing. A
  phone whose list of cameras is empty, and a list that cannot be read,
  are reported to nobody.
- After a failed start it never tries again. With the permission then
  given in the phone's settings, the page stayed dead until it was left
  and opened again (seen on the phone).
- Android shows its permission dialog twice at most; after the second
  "Don't allow" it answers without one. The camera plugin has one error
  code for both, so the app cannot tell the first refusal from the
  second.
- The app had no way to open its own page of the phone's settings.
- The package's light button and its switch-camera button have no words
  for a screen reader.
- The package draws its light button at the moment of the tap, before
  the phone has switched the light, and not again afterwards. Its icon
  showed the state the light had just left. (Found in an emulator while
  this was built; nobody had noticed, because the light itself is seen.)

A prediction that was wrong: the review, and the plan after it, said the
screen is black. On the phone it is the scan frame, empty, over the
page's own background. The finding itself held: no word, and no button
that helps.

Two predictions of the plan were wrong as well, and each stopped the
build until it was decided: that the words given to the light button
would follow the light (they were one tap behind, D140), and that an
emulator without a camera would answer with an empty list of cameras
(D141).

The decisions were taken one at a time (`PLAN.md`, D128 to D141).

## Decision

1. **One shared widget shows the camera of both scan pages**
   (`lib/core/widgets/camera_scan_view.dart`). It has three states:
   asking the phone for its cameras, reading (the package's widget is on
   the screen and owns the camera), and failed with a reason. In the
   failed state the camera area is a sentence and the buttons that fit
   the reason. No other file under `lib/` imports the scanner package;
   a test holds that (`test/architecture/camera_scanner_gate_test.dart`).

2. **Fixed on the version the app has; the update of the scanner
   package is not part of this** (D129). Version 3 is a new major with a
   new decoding core, two changes of behaviour and an Android build file
   the app's build tools are not known to take; and it still reports
   nothing for a phone without a camera. With the scanner behind one
   widget, the update will touch one file. Of the three faults version 3
   says it fixes, none was seen to hurt on the phone: the area that is
   read is a little LARGER than the frame that is drawn, the camera was
   closed every time the page was left, and scanning went on after the
   app had been in the background. Not chosen: the update inside this
   change; the update first.

3. **Three reasons get a sentence** (D130): the camera is refused (the
   package reports it); the phone has no camera, or its list of cameras
   cannot be read (the package does not, so the app asks for the list
   itself, before it shows the scanner: `core/platform/device_cameras.dart`);
   the camera did not start. For the list, `camera`, the plugin the
   scanner is built on, became a named dependency. It was in the lock
   file already, at the same version; nothing was fetched and no native
   code was added. Not chosen: a watchdog on a clock, which would have
   to pause while Android's dialog is open and could show on a phone
   that is only slow.

4. **"Open settings" opens Pitak's own page of the phone's settings**
   (D131), through one method without an argument in the app's own
   Android code (`AppSettingsChannel.kt`; Android's
   `ACTION_APPLICATION_DETAILS_SETTINGS` with the app's own package
   name, which is read on the Android side). Dart sends nothing. It
   needs no permission, and nothing leaves the phone. The button is
   built only where that Android side exists. Back from the settings,
   the scan page tries the camera again by itself, once. Only then: a
   page that tried at every return to the front would ask again the
   moment the user said "Don't allow", because Android's own dialog also
   sends the app away and brings it back. The trip is not exempt from
   the app lock: with the lock on, Pitak asks for the fingerprint on the
   way back, as after any time in the background. Not chosen: words
   only ("Settings › Apps › …" differs from maker to maker); a package.

5. **"Enter it by hand" on the ISBN scan page only** (D132). From a
   form it closes the scan page: the ISBN field is underneath. From the
   Library's "Scan to add" it closes the scan page and opens the "Add to
   library" sheet. It closes the page without a value, exactly as Back
   does. The QR pages have no such button: a QR code cannot be typed.

6. **The words** (D133), each a named constant in
   `core/widgets/camera_scan_messages.dart`:

   | State | Words | Buttons |
   |---|---|---|
   | the camera is refused | "Pitak is not allowed to use the camera." and "Allow the camera in the phone's settings to scan." | "Open settings"; on the ISBN page also "Enter it by hand" |
   | no camera | "This phone has no camera." | on the ISBN page "Enter it by hand" |
   | the camera did not start | "The camera did not start." | "Try again"; on the ISBN page also "Enter it by hand" |

   No "Try again" for a refused camera: after the second refusal it
   would do nothing that shows.

7. **The cover camera says the same two sentences in its bar** (D134):
   for a refused camera with "Open settings" in the bar, which is timed
   at six seconds as the "Undo" bar is (ADR 0029); for a phone without a
   camera without a button. Everything else keeps "Could not capture a
   photo.". Both places that photograph a cover share one function
   (`cover_camera_message.dart`). Nothing is tried again by itself
   there: the user taps the cover button again.

8. **The scanner's two built-in buttons** (D135, D140). The
   switch-camera button is gone: it has no use for reading a code. The
   light button gets words that only a screen reader speaks, "Turn on
   the light" and "Turn off the light", through the icon parameters the
   package offers. So that the words, and the icon, say what is true,
   the shared widget watches the camera the package hands over and has
   the package's widget built again when the camera's state has changed.
   Not chosen: one phrase for both states; a light button of the app's
   own; no words.

9. **The tests reach the camera in two ways** (D136). The states of the
   shared widget are driven through seams of the app's own. And ONE test
   file builds the package's real widget over a stand-in camera
   (`test/core/widgets/package_reader_widget_test.dart`) and holds what
   the app relies on in the package: a camera that cannot start is
   reported; a widget that is built anew starts the camera again; the
   light button carries its words, also when the phone answers some
   frames after the tap; each scan page hands over the settings it had
   before.

10. **The app shows and logs nothing a plugin says.** An error is sorted
    by its code into one of the reasons
    (`core/platform/camera_failures.dart`); a code that is missing or
    not known never becomes a specific reason. Of the app's own code, a
    debug build logs the error's code at most and a release build
    nothing. No failed state ever hands a code to the page (fail
    closed).

## Consequences

- A new scan page shows its camera through `CameraScanView`. The gate
  test fails a file under `lib/` that imports the scanner package.
- When `flutter_zxing` is updated and `package_reader_widget_test.dart`
  fails, the package changed something the scan pages rest on. The
  shared widget is read again, then the test is moved on purpose (the
  pattern of the pins of ADR 0027 and of `flutter_secure_storage`).
- The permissions of the app are as they were
  (`android/merged-permissions.txt`); `PRIVACY.md` now names the QR
  scans beside the ISBN scan under "Camera", which it had left out.
- A stand-in that answers in the same moment hides what happens between
  a tap and the phone's answer. The stand-in camera and the stand-in for
  the settings can hold their answer; a test about a tap uses that.
- Known limits:
  - when the scanner package's own decoding worker fails to start, the
    package still reports nothing, and the page stays as it was before
    (known from reading; not seen);
  - "This phone has no camera." was not seen on a device (D141). An
    emulator started without a camera still promises one in the system's
    feature list; the camera library then fails its start, and the page
    says "The camera did not start." with "Try again" and, on the ISBN
    page, "Enter it by hand". By reading, a device whose feature list
    names no camera answers with an empty list and gets the sentence;
    no such device was at hand. The app does not read the text of an
    error to tell the two apart;
  - "Open settings" is offered after the first refusal too, when
    Android would still ask: the app cannot tell the two apart;
  - the page tries again by itself only after its own "Open settings".
    Whoever goes to the phone's settings another way leaves the scan
    page and opens it again;
  - the cover camera does not try again by itself;
  - someone whose back camera is broken can no longer switch to the
    front one to scan;
  - where the app does not run on Android, "Open settings" is not
    offered. The error codes of iOS are sorted as they were read in the
    plugin; iOS and the desktop builds were not tried. The app ships on
    Android.
- What holds it in place: the tests of the two sortings and of the
  words (`camera_failures_test.dart`, `camera_scan_messages_test.dart`),
  of the two ports and of the Android channel (`device_cameras_test.dart`,
  `app_settings_opener_test.dart`, `AppSettingsChannelTest.kt`), of the
  shared widget in every state (`camera_scan_view_test.dart`), of the
  two pages and of the Library's "Scan to add" (`scanner_page_test.dart`,
  `qr_scan_page_test.dart`, `library_page_test.dart`), of the cover
  camera (`cover_camera_message_test.dart`, `form_cover_field_test.dart`,
  `catalogue_item_detail_page_test.dart`), the test over the package's
  real widget, and the gate.

**Seen on devices (2026-11-21).** In an emulator with Android 16, with
one made-up book and no vault: "Scan to add" on a fresh install,
Android's question, "Don't allow", and the two sentences with "Open
settings" and "Enter it by hand"; "Open settings", which opens Pitak's
page of Android's settings inside Pitak's own task; Back with nothing
allowed, the page trying once, Android's second question, and after the
second "Don't allow" the sentences again and no loop; the camera allowed
in the settings, Back, and the scan page starting the camera by itself
in the same process, with one button that a screen reader is given as
"Turn on the light"; the words following the light at each of four taps,
compared with the camera library's own log, and again after the app had
been in the background; the camera closed after Back; "Enter it by hand"
opening the "Add to library" sheet from the Library and leading back to
the form from Add book; a QR scan page with the sentences, "Open
settings" and no second button; "Replace cover" with the bar and its
"Open settings", the bar gone by itself, and nothing tried again after
the settings. With Android's font at its largest, at 411 dp and at 320
dp, every button keeps its words on one line; the sentences take two and
three lines. The same emulator started without a camera: see the known
limits. The device's log held no crash and, of Pitak's own lines, only
the debug build's error code; in the run without a camera the camera
library wrote error lines of its own. Not tried there: a real barcode or
QR code, a real torch, the app lock on the way back from the settings, a
screen reader (the image has none). On a phone with Android 14, in a
debug build over an install with made-up data: by the maintainer's hand
a book's barcode was read on "Scan ISBN barcode" and led to the Add book
form, and the torch went on and off with its icon. Through `adb`, while
the maintainer watched: the words of the light button followed the light
at each of four taps; with the camera taken away in the phone's
settings, the sentences and the buttons on the ISBN page and on a QR
page, "Open settings" and Back with nothing allowed (one try, no loop),
"Enter it by hand" from the Library and from the form, and the cover
camera's bar; then, with the camera allowed in the settings, the QR page
starting the camera by itself in the same process. Looked at and
accepted by the maintainer; which points of the maintainer's own look
were made was not said. Not tried on the phone: the way back from the
settings with the app lock on, a library QR being read, the largest
font, a screen reader.
