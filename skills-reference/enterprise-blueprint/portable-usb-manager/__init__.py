"""
portable-usb-manager skill — Hermes-compatible package.

Consolidates usb-manager + unified-usb-skill + portable-linux-usb into one
robust USB-first portable Linux management skill. Distilled from the
USB-Hemlock platform work (CL-001 through CL-024).

Re-exports skill metadata for programmatic discovery.
"""

__skill__ = "portable-usb-manager"
__version__ = "2.0.9"
__provenance__ = ("usb-manager", "unified-usb-skill", "portable-linux-usb",
                  "usb-system payload (usb-hemlock-project menu.sh + usb/)")
__all__ = ["__skill__", "__version__", "__provenance__"]
