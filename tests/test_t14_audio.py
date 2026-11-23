"""Apply the installed fragment with WirePlumber's matcher; no daemon or sound card."""

import json
import os
import unittest


@unittest.skipUnless("T14_AUDIO_CONF" in os.environ, "run the t14-audio flake check")
class T14Audio(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Both GI and this typelib are supplied by the Nix check, not system Python.
        import gi  # pyright: ignore[reportMissingImports]

        gi.require_version("Wp", "0.5")
        from gi.repository import Wp  # pyright: ignore[reportMissingImports]

        cls.wp = Wp
        Wp.init(Wp.InitFlags.PIPEWIRE)
        cls.conf = Wp.Conf.new(os.environ["T14_AUDIO_CONF"], None)
        if not cls.conf.open():
            raise RuntimeError("WirePlumber could not open the Home Manager fragment")

    def apply(self, section, props):
        obj = self.wp.Properties.new_empty()
        for key, value in props.items():
            obj.set(key, value)
        rules = self.conf.get_section(section)
        self.assertIsNotNone(rules, section)
        self.wp.json_utils_match_rules_update_properties(rules, obj)
        return obj

    def test_only_yeti_prefers_analog_duplex(self):
        def profile(product):
            card = {
                "device.api": "alsa",
                "device.vendor.id": "0x046d",
                "device.product.id": product,
            }
            return self.apply("device.profile.priority.rules", card).get("priorities")

        self.assertEqual(
            json.loads(profile("0x0ab7")), ["output:analog-stereo+input:analog-stereo"]
        )
        self.assertIsNone(profile("0x0001"))

    def priority(self, initial, props):
        props = {
            **props,
            "priority.session": str(initial),
            "priority.driver": str(initial),
        }
        node = self.apply("monitor.alsa.rules", props)
        self.assertEqual(node.get("priority.driver"), str(initial), props)
        return int(node.get("priority.session"))

    def test_capture_fallback_and_playback_order(self):
        def usb(component, direction, profile="analog-stereo"):
            return {
                "alsa.components": component,
                "media.class": f"Audio/{direction}",
                "device.profile.name": profile,
            }

        yeti, display = "USB046d:0ab7", "USB05ac:1114"
        internal = "alsa_input.pci-0000_c4_00.6.HiFi__Mic"
        laptop = self.priority(2000, {"node.name": internal + "1__source"})
        display_mic = self.priority(2100, usb(display, "Source", "mono-fallback"))
        self.assertEqual(self.priority(2109, usb(yeti, "Source")), 2400)
        self.assertEqual(laptop, 2300)
        self.assertEqual(display_mic, 2100)
        self.assertEqual(
            self.priority(2000, {"node.name": internal + "2__source"}), 2000
        )
        headphones = self.priority(1109, usb(yeti, "Sink"))
        self.assertEqual(self.priority(1109, usb(display, "Sink")), 1250)
        self.assertEqual(headphones, 1109)
        self.assertEqual(self.priority(1000, usb("USB0000:0000", "Sink")), 1000)


if __name__ == "__main__":
    unittest.main()
