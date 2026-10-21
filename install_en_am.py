import argostranslate.package as pkg

print("Updating package index...")
pkg.update_package_index()

print("Looking for English → Amharic...")
avail = pkg.get_available_packages()
target = [p for p in avail if p.from_code == 'en' and p.to_code == 'am']

if target:
    print("Downloading model (~200 MB)...")
    path = target[0].download()
    print("Installing...")
    pkg.install_from_path(path)
    print("✅ English → Amharic model installed.")
else:
    print("❌ Could not find en→am package.")
    print("Available packages:")
    for p in avail:
        print(f"  {p.from_code} → {p.to_code}")