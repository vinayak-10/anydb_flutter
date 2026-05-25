import os
import sys
import subprocess

def convert_to_png(source_path, dest_path):
    if not os.path.exists(source_path):
        print(f"Source file not found: {source_path}")
        return False
        
    print(f"Converting: {source_path} -> {dest_path}")
    
    # Ensure Pillow is installed
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is not installed. Installing now...")
        subprocess.run([sys.executable, "-m", "pip", "install", "Pillow"], check=True)
        from PIL import Image
            
    try:
        with Image.open(source_path) as img:
            img.save(dest_path, format="PNG")
            print("Conversion successful!")
            return True
    except Exception as e:
        print(f"Error converting image: {e}")
        return False

if __name__ == "__main__":
    # Correct actual source files inside the brain directory
    sources = [
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_concept_1_1779601856949.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_concept_2_1779601879691.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_concept_3_1779601898530.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_concept_4_1779601921358.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_concept_5_1779601938505.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_option_a_1779603107904.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_option_b_1779603132505.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_1779603414169.jpg",
        "/home/ruggedcoder/.gemini/antigravity-cli/brain/6c6e15b1-d4b6-4024-9a85-0cde14b40090/anydb_logo_1779603971590.png"
    ]
    
    # Destination directory inside the user's workspace
    dest_dir = "/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/logo_concepts"
    os.makedirs(dest_dir, exist_ok=True)
    print(f"Created/verified destination directory: {dest_dir}")
    
    # Destination final PNG files (fully compliant PNG binaries in project workspace)
    destinations = [
        os.path.join(dest_dir, "anydb_logo_concept_1.png"),
        os.path.join(dest_dir, "anydb_logo_concept_2.png"),
        os.path.join(dest_dir, "anydb_logo_concept_3.png"),
        os.path.join(dest_dir, "anydb_logo_concept_4.png"),
        os.path.join(dest_dir, "anydb_logo_concept_5.png"),
        os.path.join(dest_dir, "anydb_logo_option_a.png"),
        os.path.join(dest_dir, "anydb_logo_option_b.png"),
        os.path.join(dest_dir, "anydb_logo_terracotta_outline.png"),
        os.path.join(dest_dir, "anydb_logo_hybrid_blend.png")
    ]
    
    success_count = 0
    for src, dest in zip(sources, destinations):
        if convert_to_png(src, dest):
            success_count += 1
            
    print(f"\nSuccessfully converted {success_count} of {len(sources)} images to PNG!")
