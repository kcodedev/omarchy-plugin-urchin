from __future__ import annotations

import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader("urchinctl", str(ROOT / "bin" / "urchinctl"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
urchinctl = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(urchinctl)


KEYMAP = r'''
/* braces in comments must not confuse the parser: { } */
/ {
  keymap {
    compatible = "zmk,keymap";
    base_layer {
      label = "Base";
      bindings = <
        &kp Q  &kp W // the first row
        &mo 1  &kp LC(SPACE)
      >;
    };
    settings_layer {
      label = "Settings";
      bindings = <&bootloader &none &bt BT_SEL 0 &studio_unlock>;
    };
  };
};
'''


class KeymapTests(unittest.TestCase):
    def test_parses_labels_and_complete_bindings(self):
        layers = urchinctl.parse_layers(KEYMAP)
        self.assertEqual([layer["label"] for layer in layers], ["Base", "Settings"])
        self.assertEqual(layers[0]["bindings"], ["&kp Q", "&kp W", "&mo 1", "&kp LC(SPACE)"])

    def test_single_replacement_preserves_comments_and_neighbors(self):
        layers = urchinctl.parse_layers(KEYMAP)
        start, end = layers[0]["_ranges"][1]
        changed = KEYMAP[:start] + "&kp E" + KEYMAP[end:]
        self.assertIn("&kp E // the first row", changed)
        self.assertIn("&kp Q", changed)
        self.assertIn("&mo 1", changed)

    def test_atomic_edit_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "urchin.keymap"
            path.write_text(KEYMAP)
            layers = urchinctl.parse_layers(path.read_text())
            selected = urchinctl.choose_layer(layers, "Base")
            start, end = selected["_ranges"][2]
            text = path.read_text()
            urchinctl.atomic_replace(path, text[:start] + "&to 2" + text[end:])
            reparsed = urchinctl.parse_layers(path.read_text())
            self.assertEqual(reparsed[0]["bindings"][2], "&to 2")

    def test_rejects_unsafe_binding(self):
        with self.assertRaises(urchinctl.UrchinError):
            urchinctl.validate_binding("&kp Q; rm -rf /tmp/nope")


class BuildMatrixTests(unittest.TestCase):
    def test_reads_zmk_include_matrix(self):
        yaml = '''---
include:
  - board: nice_nano_v2
    shield: urchin_left nice_view_adapter
    snippet: studio-rpc-usb-uart
    cmake-args: -DCONFIG_ZMK_STUDIO=y
  - board: nice_nano_v2
    shield: settings_reset
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "build.yaml"
            path.write_text(yaml)
            entries = urchinctl.parse_build_matrix(path)
        self.assertEqual(urchinctl.target_name(entries[0]), "left")
        self.assertEqual(entries[0]["snippet"], "studio-rpc-usb-uart")
        self.assertEqual(urchinctl.target_name(entries[1]), "reset")


def prop(type_name, data):
    return {"type": type_name, "data": data}


class BatteryTests(unittest.TestCase):
    def objects(self, *, connected=True, two_batteries=False):
        device = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
        result = {
            device: {
                "org.bluez.Device1": {
                    "Name": prop("s", "urchin"),
                    "Alias": prop("s", "Urchin"),
                    "Connected": prop("b", connected),
                    "Paired": prop("b", True),
                }
            },
            device + "/service0010": {
                "org.bluez.GattService1": {"UUID": prop("s", urchinctl.BLUEZ_BATTERY_SERVICE_UUID)}
            },
            device + "/service0010/char0011": {
                "org.bluez.GattCharacteristic1": {
                    "UUID": prop("s", urchinctl.BLUEZ_BATTERY_LEVEL_UUID),
                    "Service": prop("o", device + "/service0010"),
                    "Handle": prop("q", 17),
                }
            },
        }
        if two_batteries:
            result[device + "/service0015"] = {
                "org.bluez.GattService1": {"UUID": prop("s", urchinctl.BLUEZ_BATTERY_SERVICE_UUID)}
            }
            result[device + "/service0015/char0016"] = {
                "org.bluez.GattCharacteristic1": {
                    "UUID": prop("s", urchinctl.BLUEZ_BATTERY_LEVEL_UUID),
                    "Service": prop("o", device + "/service0015"),
                    "Handle": prop("q", 22),
                }
            }
        return result

    def test_reads_left_battery(self):
        status = urchinctl.battery_status_from_objects(self.objects(), "urchin", lambda _path: 91)
        self.assertEqual(status["left"], 91)
        self.assertIsNone(status["right"])
        self.assertTrue(status["connected"])

    def test_maps_battery_services_by_handle_to_left_and_right(self):
        values = iter((91, 74))
        status = urchinctl.battery_status_from_objects(
            self.objects(two_batteries=True), "urchin", lambda _path: next(values)
        )
        self.assertEqual(status["levels"], [91, 74])
        self.assertEqual((status["left"], status["right"]), (91, 74))

    def test_does_not_read_stale_values_while_disconnected(self):
        status = urchinctl.battery_status_from_objects(
            self.objects(connected=False), "urchin", lambda _path: self.fail("reader called")
        )
        self.assertFalse(status["connected"])
        self.assertEqual(status["levels"], [])


if __name__ == "__main__":
    unittest.main()
