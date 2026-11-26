#!/usr/bin/env python3
r"""Configure a fresh generic AVD for Samsung-dimension, stock-Android layout QA.

Preparation:
  avdmanager create avd -n NAME -k system-images\;android-36\;google_apis\;x86_64
  python prepare_samsung_foldable_avd.py --profile galaxy-z-fold8 \
      --avd-name NAME --metadata-output artifacts/profile.json

Boot with -feature SupportPixelFold -writable-system -no-snapshot -wipe-data.
After boot, install the native framework configuration, before installing/running
the reader:
  python prepare_samsung_foldable_avd.py --initialize-guest \
      --serial emulator-5554 --profile-metadata artifacts/profile.json

The oddly named SupportPixelFold feature is the emulator's independent-cover
engine. The AVD is generic and all geometry is supplied here, from Samsung specs.
It is not a renamed Pixel AVD or an emulator running Samsung firmware.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


CATALOG = Path(__file__).with_name("samsung_foldable_profiles.json")
OVERLAY_PACKAGE = "com.mushaf.qa.samsung_foldable"
# Android16 PackagePartitions deliberately does not scan /system/overlay.
# /system_ext/overlay is scanned by PackageManager and zygote and retains the
# POLICY_SYSTEM policy needed by this preinstalled framework configuration.
OVERLAY_PARTITION = "system_ext"
OVERLAY_ROOT = f"/{OVERLAY_PARTITION}/overlay"
OVERLAY_DIRECTORY = f"{OVERLAY_ROOT}/MushafSamsungLayout"
OVERLAY_APK_PATH = f"{OVERLAY_DIRECTORY}/MushafSamsungLayout.apk"
# These are the AOSP emulator's built-in panel addresses, not Samsung identifiers.
INNER_ADDRESS = "4619827259835644672"
COVER_ADDRESS = "4619827551948147201"


def run(argv: list[str], *, timeout: int = 120, check: bool = True) -> str:
    result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    output = (result.stdout + result.stderr).strip()
    if check and result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {argv!r}\n{output}")
    return output


def read_ini(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith(("#", ";")):
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def write_ini(path: Path, values: dict[str, str]) -> None:
    path.write_text("\n".join(f"{key}={value}" for key, value in sorted(values.items())) + "\n")


def xml_write(path: Path, root: ET.Element) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    path.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n")


def build_profile(profile_id: str) -> dict:
    catalog = json.loads(CATALOG.read_text())
    if profile_id not in catalog["profiles"]:
        raise ValueError(f"Unknown Samsung profile: {profile_id}")
    profile = copy.deepcopy(catalog["profiles"][profile_id])
    for key in ("schemaVersion", "emulation", "sources", "assumptions"):
        profile[key] = copy.deepcopy(catalog[key])
    profile["profileId"] = profile_id
    inner = profile["displays"]["inner"]
    profile["hinge"] = {
        "orientation": "vertical", "type": "fold",
        "x": inner["width"] // 2, "y": 0, "width": 0, "height": inner["height"],
        "postures": {"closed": 1, "halfOpened": 2, "open": 3},
        "guestDeviceStates": {"closed": 0, "halfOpened": 1, "open": 2},
        "angleRanges": {"closed": [0, 30], "halfOpened": [30, 150], "open": [150, 180]},
        "defaultAngles": {"closed": 0, "halfOpened": 90, "open": 180},
    }
    profile["nativeConfiguration"] = {
        "engineFeature": "SupportPixelFold",
        "overlayPackage": OVERLAY_PACKAGE,
        "overlayInstallPartition": OVERLAY_PARTITION,
        "overlayApkPath": OVERLAY_APK_PATH,
        "overlayTargetSdk": 28,
        "displayFeatures": f"fold-[{inner['width'] // 2},0,{inner['width'] // 2},{inner['height']}]",
        "stateToPosture": {"0": 1, "1": 2, "2": 3},
        "innerPhysicalDisplayAddress": INNER_ADDRESS,
        "coverPhysicalDisplayAddress": COVER_ADDRESS,
        "geometrySource": "Samsung panel specifications plus explicit zero-width midpoint-fold assumption",
        "postureSource": "Goldfish hinge sensor0 (in degrees) -> Android DeviceStateManager -> WindowManager",
        "requiredEmulatorArguments": ["-feature", "SupportPixelFold", "-writable-system", "-no-snapshot", "-wipe-data"],
    }
    return profile


def sdk_root(explicit: str | None) -> Path:
    value = explicit or os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not value:
        raise ValueError("Set ANDROID_SDK_ROOT/ANDROID_HOME or pass --sdk-root")
    return Path(value).expanduser().resolve()


def avd_directory(name: str, explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    base = Path(os.environ.get("ANDROID_AVD_HOME", str(Path.home() / ".android" / "avd")))
    pointer = base / f"{name}.ini"
    if pointer.exists():
        values = read_ini(pointer)
        if values.get("path"):
            return Path(values["path"]).expanduser().resolve()
    return (base / f"{name}.avd").resolve()


def write_guest_configuration(directory: Path) -> list[Path]:
    """Native sensor conditions and built-in display switching; no state override."""
    root = ET.Element("device-state-config")
    states = [
        (0, "CLOSED", "CLOSED", "OUTER", "min-inclusive", 0, "max-inclusive", 30),
        (1, "HALF_OPENED", "HALF_OPEN", "INNER", "min", 30, "max", 150),
        (2, "OPENED", "OPEN", "INNER", "min-inclusive", 150, "max-inclusive", 180),
    ]
    for number, name, physical, display, low_tag, low, high_tag, high in states:
        state = ET.SubElement(root, "device-state")
        ET.SubElement(state, "identifier").text = str(number)
        ET.SubElement(state, "name").text = name
        properties = ET.SubElement(state, "properties")
        for prop in (f"FOLDABLE_HARDWARE_CONFIGURATION_FOLD_IN_{physical}", f"FOLDABLE_DISPLAY_CONFIGURATION_{display}_PRIMARY"):
            ET.SubElement(properties, "property").text = "com.android.server.policy.PROPERTY_" + prop
        sensor = ET.SubElement(ET.SubElement(state, "conditions"), "sensor")
        ET.SubElement(sensor, "type").text = "android.sensor.hinge_angle"
        ET.SubElement(sensor, "name").text = "Goldfish hinge sensor0 (in degrees)"
        value = ET.SubElement(sensor, "value")
        ET.SubElement(value, low_tag).text = str(low)
        ET.SubElement(value, high_tag).text = str(high)
    device_file = directory / "devicestate" / "device_state_configuration.xml"
    xml_write(device_file, root)

    layouts = ET.Element("layouts")
    for number in (0, 1, 2):
        layout = ET.SubElement(layouts, "layout")
        ET.SubElement(layout, "state").text = str(number)
        for address, active in ((INNER_ADDRESS, number != 0), (COVER_ADDRESS, number == 0)):
            attrs = {"enabled": str(active).lower()}
            if active:
                attrs["defaultDisplay"] = "true"
            display = ET.SubElement(layout, "display", attrs)
            ET.SubElement(display, "address").text = address
    layout_file = directory / "displayconfig" / "display_layout_configuration.xml"
    xml_write(layout_file, layouts)

    settings = ET.Element("display-settings")
    ET.SubElement(settings, "config", {"identifier": "0"})
    for address in (INNER_ADDRESS, COVER_ADDRESS):
        ET.SubElement(settings, "display", {"name": "local:" + address, "ignoreOrientationRequest": "true"})
    settings_file = directory / "display_settings.xml"
    xml_write(settings_file, settings)
    permissions = ET.Element("permissions")
    ET.SubElement(permissions, "feature", {"name": "android.hardware.sensor.hinge_angle"})
    feature_file = directory / "extra_feature.xml"
    xml_write(feature_file, permissions)
    return [device_file, layout_file, settings_file, feature_file]


def write_overlay(directory: Path, profile: dict) -> Path:
    android = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", android)
    manifest = ET.Element("manifest", {"package": OVERLAY_PACKAGE, f"{{{android}}}versionCode": "1", f"{{{android}}}versionName": "1"})
    # A preinstalled system RRO uses the legacy device-configuration contract.
    # It is not installed as an ordinary user application or shipped in Mushaf.
    ET.SubElement(manifest, "uses-sdk", {f"{{{android}}}minSdkVersion": "28", f"{{{android}}}targetSdkVersion": "28"})
    ET.SubElement(manifest, "overlay", {f"{{{android}}}targetPackage": "android", f"{{{android}}}isStatic": "true", f"{{{android}}}priority": "999"})
    ET.SubElement(manifest, "application", {f"{{{android}}}hasCode": "false", f"{{{android}}}label": "Samsung dimensions on stock Android"})
    xml_write(directory / "AndroidManifest.xml", manifest)

    resources = ET.Element("resources")
    ET.SubElement(resources, "string", {"name": "config_display_features", "translatable": "false"}).text = profile["nativeConfiguration"]["displayFeatures"]
    arrays = {
        "config_device_state_postures": ("string-array", ["0:1", "1:2", "2:3"]),
        "config_displayUniqueIdArray": ("string-array", ["local:" + INNER_ADDRESS, "local:" + COVER_ADDRESS]),
        "config_foldedDeviceStates": ("integer-array", [0]),
        "config_halfFoldedDeviceStates": ("integer-array", [1]),
        "config_openDeviceStates": ("integer-array", [2]),
        "config_deviceTabletopRotations": ("integer-array", [90, 270]),
    }
    for name, (tag, values) in arrays.items():
        array = ET.SubElement(resources, tag, {"name": name, "translatable": "false"})
        for value in values:
            ET.SubElement(array, "item").text = str(value)
    for name, value in {
        "config_supportsConcurrentInternalDisplays": "false",
        "config_isDisplayHingeAlwaysSeparating": "false",
        "config_windowManagerHalfFoldAutoRotateOverride": "false",
        "config_supportsMultiWindow": "true",
        "config_supportsSplitScreenMultiWindow": "true",
    }.items():
        ET.SubElement(resources, "bool", {"name": name}).text = value
    xml_write(directory / "res" / "values" / "config.xml", resources)
    return directory


def prepare(args: argparse.Namespace) -> None:
    if not args.profile or not args.avd_name or not args.metadata_output:
        raise ValueError("Preparation requires --profile, --avd-name and --metadata-output")
    profile = build_profile(args.profile)
    sdk = sdk_root(args.sdk_root)
    avd = avd_directory(args.avd_name, args.avd_dir)
    config_path = avd / "config.ini"
    if not config_path.is_file():
        raise ValueError(f"Create a generic AVD first; missing {config_path}")
    if any(avd.glob("userdata-qemu.img*")):
        raise ValueError("Refusing to reconfigure an AVD that has booted; create a fresh isolated QA AVD")
    config = read_ini(config_path)
    initial_name = config.get("hw.device.name", "")
    if "pixel" in initial_name.lower():
        raise ValueError("Use avdmanager without --device; a Pixel profile cannot be relabelled as Samsung")
    image = Path(config.get("image.sysdir.1", ""))
    image = image if image.is_absolute() else sdk / image
    if not (image / "data").is_dir():
        raise ValueError(f"Installed system image must contain its native data seed: {image / 'data'}")
    source_properties = read_ini(image / "source.properties")
    api = int(source_properties.get("AndroidVersion.ApiLevel", "0"))
    if api != 36 or source_properties.get("SystemImage.Abi") != "x86_64" or source_properties.get("SystemImage.TagId") != "google_apis":
        raise ValueError("Use the API36 google_apis x86_64 userdebug system image for this native configuration")

    # Replace every generic hardware value, so no inherited device geometry or
    # cutout configuration silently participates in the Samsung-dimension test.
    config = {key: value for key, value in config.items() if not key.startswith("hw.")}
    inner, cover, hinge = profile["displays"]["inner"], profile["displays"]["cover"], profile["hinge"]
    config.update({
        "AvdId": args.avd_name, "avd.ini.displayname": profile["displayName"] + " (stock Android)",
        "PlayStore.enabled": "false", "disk.dataPartition.size": "8G",
        "fastboot.forceColdBoot": "yes", "fastboot.forceFastBoot": "no",
        "hw.device.name": args.profile, "hw.device.manufacturer": "Mushaf QA (Samsung dimensions)",
        "hw.cpu.arch": "x86_64", "hw.cpu.ncore": "4", "hw.ramSize": "4096",
        "hw.lcd.width": str(inner["width"]), "hw.lcd.height": str(inner["height"]),
        "hw.lcd.density": str(inner["densityDpi"]), "hw.lcd.depth": "32",
        "hw.displayRegion.0.1.width": str(cover["width"]), "hw.displayRegion.0.1.height": str(cover["height"]),
        "hw.displayRegion.0.1.xOffset": "0", "hw.displayRegion.0.1.yOffset": "0",
        "hw.sensor.hinge": "yes", "hw.sensor.hinge.count": "1", "hw.sensor.hinge.type": "1",
        "hw.sensor.hinge.sub_type": "0", "hw.sensor.hinge.ranges": "0-180", "hw.sensor.hinge.defaults": "180",
        "hw.sensor.hinge.areas": f"{hinge['x']}-0-0-{hinge['height']}",
        "hw.sensor.posture_list": "1,2,3", "hw.sensor.hinge_angles_posture_definitions": "0-30-0,30-150-90,150-180-180",
        "hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture": "1",
        "hw.accelerometer": "yes", "hw.gyroscope": "yes", "hw.sensors.orientation": "yes",
        "hw.keyboard": "yes", "hw.keyboard.lid": "yes", "hw.mainKeys": "no",
        "hw.dPad": "no", "hw.trackBall": "no", "hw.gps": "yes", "hw.battery": "yes",
        "hw.camera.back": "none", "hw.camera.front": "none", "hw.audioInput": "no",
        "hw.gpu.enabled": "yes", "hw.gpu.mode": "software", "hw.screen": "multi-touch",
        "hw.initialOrientation": profile["naturalInnerOrientation"],
        "skin.dynamic": "yes", "skin.name": f"{inner['width']}x{inner['height']}",
        "skin.path": f"{inner['width']}x{inner['height']}", "showDeviceFrame": "no",
    })
    write_ini(config_path, config)
    seed = image / "data" / "misc" / args.profile
    guest_files = write_guest_configuration(seed)
    overlay = write_overlay(avd / "samsung-layout-overlay", profile)
    profile["runtime"] = {
        "avdName": args.avd_name, "avdDirectory": str(avd), "sdkRoot": str(sdk),
        "systemImageDirectory": str(image.resolve()), "systemImageApi": api,
        "systemImageRevision": source_properties.get("Pkg.Revision"),
        "overlaySourceDirectory": str(overlay), "nativeSeedDirectory": str(seed),
        "avdConfigSha256": hashlib.sha256(config_path.read_bytes()).hexdigest(),
        "nativeSeedSha256": {str(path.relative_to(seed)): hashlib.sha256(path.read_bytes()).hexdigest() for path in guest_files},
        "initialized": False,
    }
    output = Path(args.metadata_output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(profile, indent=2, ensure_ascii=False) + "\n")
    print(f"Prepared {args.profile}: inner {inner['width']}×{inner['height']}, cover {cover['width']}×{cover['height']}, stock Android")
    print(f"Metadata: {output}")


def build_overlay(profile: dict) -> Path:
    sdk = Path(profile["runtime"]["sdkRoot"])
    directory = Path(profile["runtime"]["overlaySourceDirectory"])
    build_tools = sdk / "build-tools" / "36.0.0"
    aapt = build_tools / "aapt2"
    signer = build_tools / "apksigner"
    framework = sdk / "platforms" / "android-36" / "android.jar"
    for path in (aapt, signer, framework):
        if not path.exists():
            raise ValueError(f"Install platforms;android-36 and build-tools;36.0.0; missing {path}")
    compiled = directory / "compiled.zip"
    unsigned = directory / "overlay-unsigned.apk"
    signed = directory / "MushafSamsungLayout.apk"
    run([str(aapt), "compile", "--dir", str(directory / "res"), "-o", str(compiled)])
    run([str(aapt), "link", "-o", str(unsigned), "-I", str(framework), "--manifest", str(directory / "AndroidManifest.xml"), "--auto-add-overlay", str(compiled)])
    key = directory / "qa-overlay.keystore"
    if not key.exists():
        run(["keytool", "-genkeypair", "-keystore", str(key), "-storepass", "android", "-keypass", "android", "-alias", "qa-overlay", "-dname", "CN=Mushaf Emulator Layout QA", "-keyalg", "RSA", "-keysize", "2048", "-validity", "3650", "-noprompt"])
    run([str(signer), "sign", "--ks", str(key), "--ks-key-alias", "qa-overlay", "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", str(signed), str(unsigned)])
    return signed


def initialize_guest(args: argparse.Namespace) -> None:
    if not args.profile_metadata or not args.serial:
        raise ValueError("--initialize-guest requires --serial and --profile-metadata")
    metadata_path = Path(args.profile_metadata).resolve()
    profile = json.loads(metadata_path.read_text())
    expected = build_profile(profile["profileId"])
    if profile["emulation"] != expected["emulation"] or profile["displays"] != expected["displays"]:
        raise ValueError("Metadata does not match the checked-in Samsung stock-Android profile")
    sdk = Path(profile["runtime"]["sdkRoot"])
    adb = str(sdk / "platform-tools" / "adb")

    def command(*argv: str, timeout: int = 120, check: bool = True) -> str:
        return run([adb, "-s", args.serial, *argv], timeout=timeout, check=check)

    boot_id_pattern = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", re.IGNORECASE)

    def wait_boot(timeout: int = 300, previous_boot_id: str | None = None) -> str:
        """Require a new kernel boot after reboot, completed Android boot and PM."""
        deadline = time.monotonic() + timeout
        last_state = "ADB unavailable"

        def remaining_timeout() -> int:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            return max(1, min(15, int(remaining)))

        while time.monotonic() < deadline:
            try:
                boot_id = command("shell", "cat", "/proc/sys/kernel/random/boot_id", timeout=remaining_timeout(), check=False).strip()
                if not boot_id_pattern.fullmatch(boot_id):
                    last_state = "ADB unavailable or kernel boot ID unreadable"
                elif boot_id == previous_boot_id:
                    # adb reboot can return before transport drops. The previous
                    # boot's sys.boot_completed=1 must never satisfy this wait.
                    last_state = f"still on previous kernel boot {boot_id}"
                else:
                    completed = command("shell", "getprop", "sys.boot_completed", timeout=remaining_timeout(), check=False).strip()
                    last_state = f"kernel boot {boot_id}, sys.boot_completed={completed!r}"
                    if completed == "1":
                        package = command("shell", "pm", "path", "android", timeout=remaining_timeout(), check=False)
                        if re.search(r"^package:/\S+", package, re.MULTILINE):
                            return boot_id
                        last_state += ", PackageManager not ready"
            except (TimeoutError, subprocess.TimeoutExpired):
                last_state = "timed out waiting for an ADB boot-readiness response"
            time.sleep(min(2, max(0, deadline - time.monotonic())))
        raise RuntimeError(f"Emulator did not reach a ready boot within {timeout} seconds: {last_state}")

    def reboot_and_wait() -> str:
        previous_boot_id = command("shell", "cat", "/proc/sys/kernel/random/boot_id", timeout=15).strip()
        if not boot_id_pattern.fullmatch(previous_boot_id):
            raise RuntimeError("Cannot verify reboot completion without a valid current kernel boot ID")
        command("reboot")
        return wait_boot(previous_boot_id=previous_boot_id)

    def root() -> None:
        output = command("root")
        if "cannot run as root" in output:
            raise RuntimeError("Use a google_apis userdebug image, not a Google Play image")
        # adbd itself may restart here without changing the kernel boot ID.
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                timeout = max(1, min(10, int(deadline - time.monotonic())))
                if command("shell", "id", "-u", timeout=timeout, check=False).strip() == "0":
                    return
            except subprocess.TimeoutExpired:
                pass
            time.sleep(min(1, max(0, deadline - time.monotonic())))
        raise RuntimeError("Native emulator configuration requires a rootable QA image; adbd was not root within 60 seconds")

    def requests_reboot(output: str) -> bool:
        for line in output.lower().splitlines():
            if "reboot" in line and not re.search(r"\b(?:no|not)\b.*\breboot\b|\breboot\b.*\bnot\b", line):
                return True
        return False

    def ensure_writable_system() -> str:
        diagnostics = ["disable-verity: " + command("disable-verity", check=False)]
        verity_reboot_pending = requests_reboot(diagnostics[0])
        # Verity and overlayfs can each request a separate reboot. Four attempts
        # allow those transitions while capping this path at three reboots.
        for attempt in range(1, 5):
            output = command("remount", check=False)
            diagnostics.append(f"remount attempt {attempt}: {output}")
            needs_reboot = verity_reboot_pending or requests_reboot(output)
            if not needs_reboot:
                probe = f"{OVERLAY_DIRECTORY}/.qa-write-probe"
                try:
                    command("shell", "mkdir", "-p", OVERLAY_DIRECTORY)
                    command("shell", "touch", probe)
                    command("shell", "rm", "-f", probe)
                    return "\n".join(diagnostics)
                except RuntimeError as error:
                    diagnostics.append(f"write probe failed: {error}")
            if attempt < 4:
                print(f"Preparing writable emulator /{OVERLAY_PARTITION}: reboot after remount attempt {attempt}", flush=True)
                reboot_and_wait()
                root()
                verity_reboot_pending = False
        raise RuntimeError(f"Overlay partition /{OVERLAY_PARTITION} is not writable after four remount attempts and at most three reboots. Start with -writable-system.\n" + "\n".join(diagnostics))

    wait_boot()
    root()
    if command("shell", "getprop", "ro.build.version.sdk").strip() != "36":
        raise RuntimeError("The running emulator is not the prepared API36 image")
    avd_name = command("emu", "avd", "name").splitlines()[0].strip()
    if avd_name != profile["runtime"]["avdName"]:
        raise RuntimeError(f"Refusing to configure unexpected AVD {avd_name!r}")
    apk = build_overlay(profile)
    remount_output = ensure_writable_system()
    destination = OVERLAY_APK_PATH
    try:
        command("shell", "mkdir", "-p", OVERLAY_DIRECTORY)
        command("shell", "chmod", "755", OVERLAY_DIRECTORY)
        command("push", str(apk), destination)
    except RuntimeError as error:
        raise RuntimeError(f"Cannot install native layout overlay. Start the disposable emulator with -writable-system.\n{remount_output}\n{error}") from error
    command("shell", "chmod", "644", destination)
    command("shell", "restorecon", "-RF", OVERLAY_DIRECTORY)
    # Android11+ ignores isStatic/priority if the partition has an overlay
    # configuration file. Keep our early-boot framework overlay immutable and
    # place it before every existing entry/merge: an included file may already
    # contain mutable overlays, after which immutable entries are invalid.
    overlay_config_path = f"{OVERLAY_ROOT}/config/config.xml"
    try:
        existing_overlay_config = command("shell", "cat", overlay_config_path)
    except RuntimeError as error:
        if "No such file" not in str(error):
            raise
    else:
        config_root = ET.fromstring(existing_overlay_config)
        if config_root.tag != "config":
            raise RuntimeError(f"Unrecognized {OVERLAY_PARTITION} overlay configuration; refusing to replace it")
        for item in list(config_root):
            if item.tag == "overlay" and item.get("package") == OVERLAY_PACKAGE:
                config_root.remove(item)
        config_root.insert(0, ET.Element("overlay", {"package": OVERLAY_PACKAGE, "enabled": "true", "mutable": "false"}))
        local_config = Path(profile["runtime"]["overlaySourceDirectory"]) / f"{OVERLAY_PARTITION}-overlay-config.xml"
        xml_write(local_config, config_root)
        command("push", str(local_config), overlay_config_path)
        command("shell", "chmod", "644", overlay_config_path)
        command("shell", "restorecon", overlay_config_path)
    # Ensure no older emulator setting can mask the native sensor/resource path.
    command("shell", "settings", "delete", "global", "display_features")
    command("shell", "settings", "delete", "global", "device_posture")
    initialized_boot_id = reboot_and_wait()
    root()
    package_path = command("shell", "pm", "path", OVERLAY_PACKAGE, check=False)
    if not re.search(r"^package:/(?:system/)?system_ext/overlay/MushafSamsungLayout/MushafSamsungLayout\.apk\s*$", package_path, re.MULTILINE):
        installed_file = command("shell", "ls", "-lZ", destination, check=False)
        raise RuntimeError(f"Native layout APK was not registered as a preinstalled system_ext overlay.\nPackageManager: {package_path}\nFile: {installed_file}")
    overlays = command("shell", "cmd", "overlay", "list", "android")
    if not re.search(r"\[x\]\s+" + re.escape(OVERLAY_PACKAGE) + r"(?:\s|$)", overlays):
        raise RuntimeError(f"Native Samsung layout overlay was not enabled:\n{overlays}")
    geometry = command("shell", "cmd", "overlay", "lookup", "android", "android:string/config_display_features")
    if profile["nativeConfiguration"]["displayFeatures"] not in geometry:
        raise RuntimeError(f"Native fold geometry mismatch: {geometry}")
    state_map = command("shell", "cmd", "overlay", "lookup", "android", "android:array/config_device_state_postures")
    if any(value not in state_map for value in ("0:1", "1:2", "2:3")):
        raise RuntimeError(f"Native closed/half/open state mapping mismatch: {state_map}")
    concurrent_displays = command("shell", "cmd", "overlay", "lookup", "android", "android:bool/config_supportsConcurrentInternalDisplays")
    if concurrent_displays.strip().lower() != "false":
        raise RuntimeError(f"Native mutually exclusive inner/cover display policy mismatch: {concurrent_displays}")
    states = command("shell", "cmd", "device_state", "print-states")
    if any(name not in states for name in ("CLOSED", "HALF_OPENED", "OPENED")):
        raise RuntimeError(f"Native sensor-driven device states missing: {states}")
    sensor = command("emu", "sensor", "get", "hinge-angle0")
    if not re.search(r"hinge-angle0\s*=\s*[-+\d.]", sensor):
        raise RuntimeError(f"Native hinge sensor unavailable: {sensor}")
    profile["runtime"].update({
        "initialized": True, "overlayApkSha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "nativeOverlayPackagePath": package_path,
        "nativeGeometryLookup": geometry, "nativeStateMapLookup": state_map,
        "nativeConcurrentInternalDisplaysLookup": concurrent_displays,
        "nativeSupportedStates": states, "nativeHingeSensor": sensor,
        "initializedBootId": initialized_boot_id,
        "emulatorVersion": run([str(sdk / "emulator" / "emulator"), "-version"], check=False),
    })
    metadata_path.write_text(json.dumps(profile, indent=2, ensure_ascii=False) + "\n")
    print(f"Native {profile['profileId']} layout ready; sensor-driven states and closed-screen feature suppression configured")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profile", choices=("galaxy-z-fold8", "galaxy-z-fold8-ultra"))
    parser.add_argument("--avd-name")
    parser.add_argument("--avd-dir")
    parser.add_argument("--sdk-root")
    parser.add_argument("--metadata-output")
    parser.add_argument("--initialize-guest", action="store_true")
    parser.add_argument("--serial")
    parser.add_argument("--profile-metadata")
    args = parser.parse_args()
    try:
        initialize_guest(args) if args.initialize_guest else prepare(args)
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"Samsung AVD configuration failed: {error}\n")


if __name__ == "__main__":
    main()
