import os
from PIL import Image

def update_launcher_icons():
    source_logo = "/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/anydb_logo.png"
    if not os.path.exists(source_logo):
        print(f"Source logo not found at {source_logo}. Please make sure it is generated first!")
        return False
        
    print(f"Loading master logo from {source_logo}...")
    img = Image.open(source_logo)
    
    # Android Mipmap dimensions
    mipmap_configs = [
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192)
    ]
    
    base_res_dir = "/home/ruggedcoder/softwares/fresh/anydb_flutter/android/app/src/main/res"
    
    for folder_suffix, size in mipmap_configs:
        dest_folder = os.path.join(base_res_dir, f"mipmap-{folder_suffix}")
        os.makedirs(dest_folder, exist_ok=True)
        dest_path = os.path.join(dest_folder, "ic_launcher.png")
        
        print(f"Resizing to {size}x{size} for mipmap-{folder_suffix} -> {dest_path}...")
        resized_img = img.resize((size, size), Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.ANTIALIAS)
        resized_img.save(dest_path, "PNG")
        
    print("\nAndroid launcher icons updated successfully!")
    return True

if __name__ == "__main__":
    update_launcher_icons()
