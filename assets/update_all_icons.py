#!/usr/bin/env python3
import os
import sys
import subprocess

def update_all_icons():
    source_logo = "/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/anydb_logo_centered.png"
    if not os.path.exists(source_logo):
        print(f"Source logo not found at {source_logo}. Please make sure it is generated first!")
        return False
        
    # Ensure Pillow is installed
    try:
        from PIL import Image, ImageOps
    except ImportError:
        print("Pillow is not installed. Installing now...")
        subprocess.run([sys.executable, "-m", "pip", "install", "Pillow"], check=True)
        from PIL import Image, ImageOps
        
    print(f"Loading master logo from {source_logo}...")
    master = Image.open(source_logo)

    # Determine resampling filter compatibility across Pillow versions
    try:
        resample_filter = Image.Resampling.LANCZOS
    except AttributeError:
        resample_filter = getattr(Image, "ANTIALIAS", Image.BICUBIC)
    
    # 1. Update Web Icons & Favicon
    web_configs = [
        ("/home/ruggedcoder/softwares/fresh/anydb_flutter/web/favicon.png", 32),
        ("/home/ruggedcoder/softwares/fresh/anydb_flutter/web/icons/Icon-192.png", 192),
        ("/home/ruggedcoder/softwares/fresh/anydb_flutter/web/icons/Icon-512.png", 512),
        ("/home/ruggedcoder/softwares/fresh/anydb_flutter/web/icons/Icon-maskable-192.png", 192),
        ("/home/ruggedcoder/softwares/fresh/anydb_flutter/web/icons/Icon-maskable-512.png", 512)
    ]
    
    for dest_path, size in web_configs:
        dest_dir = os.path.dirname(dest_path)
        os.makedirs(dest_dir, exist_ok=True)
        print(f"Generating Web Icon ({size}x{size}) -> {dest_path}...")
        resized = master.resize((size, size), resample_filter)
        resized.save(dest_path, "PNG")
        
    # 2. Update Android Icons (Legacy & Adaptive Foreground)
    android_configs = [
        ("mdpi", 48, 108),
        ("hdpi", 72, 162),
        ("xhdpi", 96, 216),
        ("xxhdpi", 144, 324),
        ("xxxhdpi", 192, 432)
    ]
    
    base_res_dir = "/home/ruggedcoder/softwares/fresh/anydb_flutter/android/app/src/main/res"
    
    for folder_suffix, legacy_size, adaptive_size in android_configs:
        dest_folder = os.path.join(base_res_dir, f"mipmap-{folder_suffix}")
        os.makedirs(dest_folder, exist_ok=True)
        
        # A. Legacy solid ic_launcher.png
        legacy_path = os.path.join(dest_folder, "ic_launcher.png")
        print(f"Generating Android Legacy Mipmap ({legacy_size}x{legacy_size}) -> {legacy_path}...")
        resized_legacy = master.resize((legacy_size, legacy_size), resample_filter)
        resized_legacy.save(legacy_path, "PNG")
        
        # B. Adaptive transparent ic_launcher_foreground.png
        # Centered and scaled to 72% so it resides safely inside the adaptive mask area
        foreground_path = os.path.join(dest_folder, "ic_launcher_foreground.png")
        print(f"Generating Android Adaptive Foreground ({adaptive_size}x{adaptive_size}) -> {foreground_path}...")
        
        # Create transparent canvas
        canvas = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        # Center target size is 72% of the canvas size
        center_size = int(adaptive_size * 0.72)
        resized_center = master.resize((center_size, center_size), resample_filter)
        
        # Paste centered
        offset = (adaptive_size - center_size) // 2
        canvas.paste(resized_center, (offset, offset))
        canvas.save(foreground_path, "PNG")
        
    print("\nWeb and Android launcher icons regenerated successfully!")
    return True

if __name__ == "__main__":
    update_all_icons()
