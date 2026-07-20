#!/usr/bin/env python3
"""
Phase 2 Validator: Mobile Flutter (iOS/Android/Web/Desktop)
Checks for pubspec, platform dirs, build configs, code signing, CI/CD, tests.
Run by ENFORCER only — not by agent.
"""

import sys
import json
import subprocess
from pathlib import Path

def find_project_root(start: Path) -> Path:
    for p in [start] + list(start.parents):
        if (p / "pubspec.yaml").exists() or (p / "pubspec.yml").exists():
            return p
    return start

def run_cmd(cmd, cwd, timeout=30):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, shell=isinstance(cmd, str))
        return r.returncode == 0, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def check_pubspec(root: Path):
    for f in ["pubspec.yaml", "pubspec.yml"]:
        p = root / f
        if p.exists():
            try:
                import yaml
                data = yaml.safe_load(p.read_text())
                name = data.get("name", "unknown")
                version = data.get("version", "0.0.0")
                deps = data.get("dependencies", {})
                dev_deps = data.get("dev_dependencies", {})
                flutter = "flutter" in deps
                return True, f"pubspec: {name} v{version} | flutter: {flutter} | deps: {len(deps)} | dev_deps: {len(dev_deps)}"
            except Exception as e:
                return False, f"Invalid pubspec: {e}"
    return False, "Missing pubspec.yaml"

def check_pubspec_lock(root: Path):
    if (root / "pubspec.lock").exists():
        return True, "pubspec.lock exists"
    return False, "Missing pubspec.lock (run flutter pub get)"

def check_platform_dirs(root: Path):
    platforms = []
    for plat in ["android", "ios", "macos", "windows", "linux", "web"]:
        p = root / plat
        if p.exists() and any(p.iterdir()):
            platforms.append(plat)
    if platforms:
        return True, f"Platform dirs: {', '.join(platforms)}"
    return False, "No platform directories (android/, ios/, macos/, windows/, linux/, web/) - run flutter create ."

def check_android_config(root: Path):
    checks = []
    if (root / "android" / "build.gradle").exists() or (root / "android" / "build.gradle.kts").exists():
        checks.append("build.gradle")
    if (root / "android" / "app" / "build.gradle").exists() or (root / "android" / "app" / "build.gradle.kts").exists():
        checks.append("app/build.gradle")
    if (root / "android" / "gradle.properties").exists():
        checks.append("gradle.properties")
    if (root / "android" / "settings.gradle").exists() or (root / "android" / "settings.gradle.kts").exists():
        checks.append("settings.gradle")
    if (root / "android" / "app" / "src" / "main" / "AndroidManifest.xml").exists():
        checks.append("AndroidManifest.xml")
    if (root / "android" / "key.properties").exists():
        checks.append("key.properties (signing)")
    if checks:
        return True, f"Android config: {', '.join(checks)}"
    return False, "Incomplete Android config (build.gradle, app/build.gradle, AndroidManifest.xml, key.properties for signing)"

def check_ios_config(root: Path):
    checks = []
    if (root / "ios" / "Runner.xcworkspace").exists():
        checks.append("Runner.xcworkspace")
    if (root / "ios" / "Runner.xcodeproj").exists():
        checks.append("Runner.xcodeproj")
    if (root / "ios" / "Runner" / "Info.plist").exists():
        checks.append("Info.plist")
    if (root / "ios" / "Flutter" / "Debug.xcconfig").exists():
        checks.append("Debug.xcconfig")
    if (root / "ios" / "Flutter" / "Release.xcconfig").exists():
        checks.append("Release.xcconfig")
    if (root / "ios" / "Podfile").exists():
        checks.append("Podfile")
    if checks:
        return True, f"iOS config: {', '.join(checks)}"
    return False, "Incomplete iOS config (Runner.xcworkspace, Info.plist, Podfile, xcconfigs)"

def check_desktop_config(root: Path):
    checks = []
    # macOS
    if (root / "macos" / "Runner" / "Info.plist").exists():
        checks.append("macOS Info.plist")
    if (root / "macos" / "Runner.xcworkspace").exists():
        checks.append("macOS xcworkspace")
    # Windows
    if (root / "windows" / "runner" / "CMakeLists.txt").exists():
        checks.append("Windows CMakeLists.txt")
    if (root / "windows" / "flutter" / "CMakeLists.txt").exists():
        checks.append("Windows flutter/CMakeLists.txt")
    # Linux
    if (root / "linux" / "CMakeLists.txt").exists():
        checks.append("Linux CMakeLists.txt")
    if checks:
        return True, f"Desktop config: {', '.join(checks)}"
    return False, "No desktop config (macOS: Info.plist, Windows: CMakeLists.txt, Linux: CMakeLists.txt)"

def check_web_config(root: Path):
    if (root / "web" / "index.html").exists():
        return True, "Web: index.html"
    return False, "Missing web/index.html"

def check_main_dart(root: Path):
    main_files = [
        "lib/main.dart",
        "lib/main_dev.dart",
        "lib/main_prod.dart",
        "lib/main_staging.dart",
    ]
    for f in main_files:
        if (root / f).exists():
            return True, f"Entry point: {f}"
    return False, "No lib/main.dart (or main_*.dart)"

def check_analysis_options(root: Path):
    for f in ["analysis_options.yaml", "analysis_options.yml"]:
        if (root / f).exists():
            return True, f"Lint config: {f}"
    return False, "Missing analysis_options.yaml (lint rules)"

def check_test_setup(root: Path):
    dirs = ["test", "test/", "integration_test"]
    for d in dirs:
        p = root / d
        if p.exists() and any(p.rglob("*_test.dart")):
            tests = list(p.rglob("*_test.dart"))
            return True, f"Tests: {d}/ ({len(tests)} test files)"
    return False, "No tests (test/ or integration_test/ with *_test.dart)"

def check_integration_tests(root: Path):
    if (root / "integration_test").exists() and any((root / "integration_test").rglob("*_test.dart")):
        tests = list((root / "integration_test").rglob("*_test.dart"))
        return True, f"Integration tests: integration_test/ ({len(tests)} files)"
    # Check for patrol, flutter_driver
    for f in ["pubspec.yaml", "pubspec.yml"]:
        p = root / f
        if p.exists():
            content = p.read_text()
            if "patrol" in content or "flutter_driver" in content or "integration_test" in content:
                return True, "Integration test deps in pubspec"
    return False, "No integration tests (integration_test/ or patrol/flutter_driver in pubspec)"

def check_code_signing(root: Path):
    items = []
    # Android
    if (root / "android" / "key.properties").exists():
        items.append("Android key.properties")
    if (root / "android" / "app" / "upload-keystore.jks").exists() or (root / "android" / "app" / "keystore.jks").exists():
        items.append("Android keystore")
    # iOS/macOS
    if (root / "ios" / "Runner.xcworkspace").exists():
        items.append("iOS workspace (signing in Xcode)")
    if (root / "macos" / "Runner.xcworkspace").exists():
        items.append("macOS workspace")
    # CI signing
    for wf in (root / ".github/workflows").glob("*.yml") if (root / ".github/workflows").exists() else []:
        content = wf.read_text()
        if "codesign" in content.lower() or "codesign" in content or "fastlane" in content.lower() or "match" in content.lower() or "certificate" in content.lower():
            items.append("CI code signing")
            break
    if items:
        return True, f"Code signing: {', '.join(items)}"
    return False, "No code signing setup (Android: key.properties+keystore, iOS: Xcode/CI, Fastlane match)"

def check_fastlane(root: Path):
    if (root / "fastlane").exists() or (root / "android" / "fastlane").exists() or (root / "ios" / "fastlane").exists():
        return True, "Fastlane configured"
    # Check Gemfile
    for f in ["Gemfile", "android/Gemfile", "ios/Gemfile"]:
        if (root / f).exists():
            content = (root / f).read_text()
            if "fastlane" in content:
                return True, f"Fastlane in {f}"
    return False, "No Fastlane (Gemfile + fastlane/ or ios/fastlane/, android/fastlane/)"

def check_codemagic_github_actions(root: Path):
    # Codemagic
    if (root / "codemagic.yaml").exists() or (root / "codemagic.yml").exists():
        return True, "Codemagic: codemagic.yaml"
    # GitHub Actions
    wf_dir = root / ".github/workflows"
    if wf_dir.exists():
        workflows = list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml"))
        flutter_wf = []
        for wf in workflows:
            content = wf.read_text()
            if "flutter" in content.lower() or "dart" in content.lower() or "very-good-cli" in content:
                flutter_wf.append(wf.stem)
        if flutter_wf:
            return True, f"GitHub Actions: {', '.join(flutter_wf)}"
    # Bitrise
    if (root / "bitrise.yml").exists() or (root / "bitrise.yaml").exists():
        return True, "Bitrise: bitrise.yml"
    # GitLab CI
    if (root / ".gitlab-ci.yml").exists():
        content = (root / ".gitlab-ci.yml").read_text()
        if "flutter" in content.lower() or "dart" in content.lower():
            return True, "GitLab CI: flutter job"
    return False, "No CI/CD for Flutter (Codemagic, GitHub Actions, Bitrise, GitLab CI)"

def check_very_good_cli(root: Path):
    # Check for very_good_cli structure
    if (root / "tool" / "very_good_cli.yaml").exists() or (root / "very_good_cli.yaml").exists():
        return True, "Very Good CLI config"
    # Check for melos (monorepo)
    if (root / "melos.yaml").exists():
        return True, "Melos monorepo"
    return False, "No Very Good CLI / Melos config (optional but recommended)"

def check_flavors(root: Path):
    # Android flavors
    android_flavors = []
    if (root / "android" / "app" / "build.gradle").exists():
        content = (root / "android" / "app" / "build.gradle").read_text()
        if "productFlavors" in content or "flavorDimensions" in content:
            android_flavors.append("Android productFlavors")
    # iOS schemes
    if (root / "ios" / "Runner.xcworkspace").exists():
        android_flavors.append("iOS schemes (Xcode)")
    if android_flavors:
        return True, f"Build flavors: {', '.join(android_flavors)}"
    return False, "No build flavors (Android productFlavors, iOS schemes)"

def check_gitignore(root: Path):
    gi = root / ".gitignore"
    if not gi.exists():
        return False, "Missing .gitignore"
    content = gi.read_text()
    required = [
        "build/", ".dart_tool/", ".flutter-plugins", ".flutter-plugins-dependencies",
        "pubspec.lock", "*.iml", ".idea/", ".vscode/", "*.jks", "*.keystore",
        "key.properties", "*.p12", "*.pem", "*.mobileprovision"
    ]
    missing = [r for r in required if r not in content]
    if missing:
        return False, f".gitignore missing: {', '.join(missing)}"
    return True, ".gitignore has Flutter/Dart patterns"

def check_localization(root: Path):
    # Check for l10n/arb files
    if (root / "lib" / "l10n").exists() and any((root / "lib" / "l10n").glob("*.arb")):
        return True, "Localization: lib/l10n/*.arb"
    if (root / "assets" / "translations").exists() or (root / "assets" / "i18n").exists():
        return True, "Localization: assets/translations or assets/i18n"
    # Check pubspec for flutter_localizations
    for f in ["pubspec.yaml", "pubspec.yml"]:
        p = root / f
        if p.exists():
            content = p.read_text()
            if "flutter_localizations" in content or "intl" in content or "easy_localization" in content:
                return True, "Localization deps in pubspec"
    return False, "No localization (lib/l10n/*.arb, assets/translations, or flutter_localizations/intl in pubspec)"

def validate(project_root: str) -> int:
    root = find_project_root(Path(project_root))
    print(f"[validate_phase2_mobile_flutter] Checking: {root}")

    checks = [
        ("pubspec.yaml", check_pubspec),
        ("pubspec.lock", check_pubspec_lock),
        ("platform dirs", check_platform_dirs),
        ("Android config", check_android_config),
        ("iOS config", check_ios_config),
        ("Desktop config", check_desktop_config),
        ("Web config", check_web_config),
        ("main.dart", check_main_dart),
        ("analysis_options", check_analysis_options),
        ("unit/widget tests", check_test_setup),
        ("integration tests", check_integration_tests),
        ("code signing", check_code_signing),
        ("Fastlane", check_fastlane),
        ("CI/CD", check_codemagic_github_actions),
        ("Very Good CLI", check_very_good_cli),
        ("build flavors", check_flavors),
        (".gitignore", check_gitignore),
        ("localization", check_localization),
    ]

    failed = []
    for name, fn in checks:
        ok, msg = fn(root)
        status = "✓" if ok else "✗"
        print(f"  {status} {name}: {msg}")
        if not ok:
            failed.append(name)

    if failed:
        print(f"\nFAILED: {len(failed)}/{len(checks)} checks failed: {', '.join(failed)}")
        return 1
    print(f"\nPASSED: All {len(checks)} checks passed")
    return 0

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print("Usage: validate_phase2_mobile_flutter.py <project_root>")
        sys.exit(0)
    if len(sys.argv) < 2:
        print("Usage: validate_phase2_mobile_flutter.py <project_root>")
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))