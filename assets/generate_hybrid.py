#!/usr/bin/env python3
import os
import sys
import subprocess

def generate_hybrid_png(dest_path, exclude_text=False):
    print(f"Generating Yantra-Prism Hybrid PNG (exclude_text={exclude_text}) at: {dest_path}")
    
    # Ensure Pillow is installed
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow is not installed. Installing now...")
        subprocess.run([sys.executable, "-m", "pip", "install", "Pillow"], check=True)
        from PIL import Image, ImageDraw, ImageFont
        
    try:
        # Create a 512x512 image with a high-quality RGB space
        size = 512
        img = Image.new("RGB", (size, size), color=(107, 21, 36)) # Velvet Crimson #6B1524
        draw = ImageDraw.Draw(img, "RGBA")
        
        # Color definitions
        gold = (229, 193, 88, 255)       # #E5C158 Gold
        gold_trans = (229, 193, 88, 64) # Translucent Gold (Top Facet)
        red_trans = (184, 58, 75, 102)   # Translucent Crimson (Left Facet)
        orange_trans = (244, 162, 97, 76) # Translucent Saffron (Right Facet)
        white = (255, 255, 255, 255)
        white_trans = (255, 255, 255, 128)
        mint = (72, 207, 203, 255)       # #48CFCB Luminous Mint Green
        
        # Y-Offset adjustment: Shift elements down by 20px when mathematical center is needed
        oy = 20 if exclude_text else 0
        
        # 1. Draw Outer Gate (Bhupura)
        draw.rectangle([80, 70 + oy, 432, 422 + oy], outline=gold, width=4)
        
        # Inner dashed rect lines
        draw.line([96, 86 + oy, 416, 86 + oy], fill=(229, 193, 88, 150), width=2)
        draw.line([96, 406 + oy, 416, 406 + oy], fill=(229, 193, 88, 150), width=2)
        draw.line([96, 86 + oy, 96, 406 + oy], fill=(229, 193, 88, 150), width=2)
        draw.line([416, 86 + oy, 416, 406 + oy], fill=(229, 193, 88, 150), width=2)
        
        # 2. Concentric Circles representing relation tracks
        draw.ellipse([136, 116 + oy, 376, 356 + oy], outline=gold, width=3)
        draw.ellipse([156, 136 + oy, 356, 336 + oy], outline=(229, 193, 88, 128), width=1)
        
        # Outer Yantra Petals (Lotus accents)
        # Top
        draw.polygon([(256, 116 + oy), (266, 126 + oy), (256, 136 + oy), (246, 126 + oy)], fill=gold)
        # Bottom
        draw.polygon([(256, 356 + oy), (266, 346 + oy), (256, 336 + oy), (246, 346 + oy)], fill=gold)
        # Left
        draw.polygon([(136, 236 + oy), (146, 226 + oy), (156, 236 + oy), (146, 246 + oy)], fill=gold)
        # Right
        draw.polygon([(376, 236 + oy), (366, 226 + oy), (356, 236 + oy), (366, 246 + oy)], fill=gold)
        
        def draw_poly(points, fill=None, outline=None, width=1):
            if fill:
                draw.polygon(points, fill=fill)
            if outline:
                draw.line(points + [points[0]], fill=outline, width=width)

        # 3. Draw the 3D Isometric Prism / Data Cube Faces
        # Top Facet
        draw_poly([(256, 156 + oy), (326, 196 + oy), (256, 236 + oy), (186, 196 + oy)], fill=gold_trans, outline=gold, width=3)
        # Left Facet
        draw_poly([(186, 196 + oy), (256, 236 + oy), (256, 316 + oy), (186, 276 + oy)], fill=red_trans, outline=gold, width=3)
        # Right Facet
        draw_poly([(256, 236 + oy), (326, 196 + oy), (326, 276 + oy), (256, 316 + oy)], fill=orange_trans, outline=gold, width=3)
        
        # 4. Yantra Triangles (Dashed overlay)
        # Ascending
        draw_poly([(256, 156 + oy), (326, 276 + oy), (186, 276 + oy)], outline=white_trans, width=2)
        # Descending
        draw_poly([(256, 316 + oy), (326, 196 + oy), (186, 196 + oy)], outline=white_trans, width=2)
        
        # 5. Nodes at vertices (Mint nodes with white rings)
        nodes = [
            (256, 156 + oy), # Top
            (256, 316 + oy), # Bottom
            (186, 196 + oy), # Left
            (326, 196 + oy), # Right
            (186, 276 + oy), # Bottom-Left
            (326, 276 + oy)  # Bottom-Right
        ]
        for nx, ny in nodes:
            draw.ellipse([nx-8, ny-8, nx+8, ny+8], fill=mint, outline=white, width=2)
            
        # Central Bindu
        draw.ellipse([256-10, 236-10 + oy, 256+10, 236+10 + oy], fill=white, outline=gold, width=3)
        
        # 6. Typography "anydb" (Only if exclude_text is False)
        if not exclude_text:
            font_loaded = False
            for font_path in [
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
                "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf",
                "Georgia-Bold",
                "serif-bold"
            ]:
                try:
                    font = ImageFont.truetype(font_path, 34)
                    text = "anydb"
                    w = draw.textlength(text, font=font)
                    draw.text((256 - w/2, 355), text, fill=gold, font=font)
                    font_loaded = True
                    print(f"Loaded premium font: {font_path}")
                    break
                except Exception:
                    continue
                    
            if not font_loaded:
                try:
                    font = ImageFont.load_default(size=30)
                    text = "anydb"
                    w = draw.textlength(text, font=font)
                    draw.text((256 - w/2, 360), text, fill=gold, font=font)
                    print("Using default fallback font")
                except Exception as e:
                    print("Using line-drawing fallback")
                    draw.text((220, 360), "anydb", fill=gold)
                    
        img.save(dest_path, "PNG")
        print(f"Image saved successfully -> {dest_path}")
        return True
        
    except Exception as e:
        print(f"Failed to generate logo: {e}")
        return False

if __name__ == "__main__":
    # Generate original layout logo with text (centered at y=236)
    generate_hybrid_png("/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/anydb_logo.png", exclude_text=False)
    generate_hybrid_png("/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/logo_concepts/anydb_logo_yantra_prism.png", exclude_text=False)
    # Generate launcher layout logo WITHOUT text (perfectly centered at y=256)
    generate_hybrid_png("/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/anydb_logo_centered.png", exclude_text=True)
