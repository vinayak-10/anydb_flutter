import os
import sys
import subprocess

def generate_hybrid_png(dest_path):
    print(f"Generating Yantra-Prism Hybrid PNG at: {dest_path}")
    
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
        
        # 1. Draw Outer Gate (Bhupura)
        # Double bordered rect (standard yantra Bhupura uses sharp, clean rectangles)
        draw.rectangle([80, 70, 432, 422], outline=gold, width=4)
        
        # Inner dashed rect (drawn with line segments for custom dash pattern)
        dashed_outline = [96, 86, 416, 406]
        # Top line
        draw.line([96, 86, 416, 86], fill=(229, 193, 88, 150), width=2)
        # Bottom line
        draw.line([96, 406, 416, 406], fill=(229, 193, 88, 150), width=2)
        # Left line
        draw.line([96, 86, 96, 406], fill=(229, 193, 88, 150), width=2)
        # Right line
        draw.line([416, 86, 416, 406], fill=(229, 193, 88, 150), width=2)
        
        # 2. Concentric Circles representing relation tracks
        draw.ellipse([136, 116, 376, 356], outline=gold, width=3)
        draw.ellipse([156, 136, 356, 336], outline=(229, 193, 88, 128), width=1)
        
        # Outer Yantra Petals (Lotus accents)
        # Top
        draw.polygon([(256, 116), (266, 126), (256, 136), (246, 126)], fill=gold)
        # Bottom
        draw.polygon([(256, 356), (266, 346), (256, 336), (246, 346)], fill=gold)
        # Left
        draw.polygon([(136, 236), (146, 226), (156, 236), (146, 246)], fill=gold)
        # Right
        draw.polygon([(376, 236), (366, 226), (356, 236), (366, 246)], fill=gold)
        
        def draw_poly(points, fill=None, outline=None, width=1):
            if fill:
                draw.polygon(points, fill=fill)
            if outline:
                draw.line(points + [points[0]], fill=outline, width=width)

        # 3. Draw the 3D Isometric Prism / Data Cube Faces
        # Top Facet
        draw_poly([(256, 156), (326, 196), (256, 236), (186, 196)], fill=gold_trans, outline=gold, width=3)
        # Left Facet
        draw_poly([(186, 196), (256, 236), (256, 316), (186, 276)], fill=red_trans, outline=gold, width=3)
        # Right Facet
        draw_poly([(256, 236), (326, 196), (326, 276), (256, 316)], fill=orange_trans, outline=gold, width=3)
        
        # 4. Yantra Triangles (Dashed overlay)
        # Ascending
        draw_poly([(256, 156), (326, 276), (186, 276)], outline=white_trans, width=2)
        # Descending
        draw_poly([(256, 316), (326, 196), (186, 196)], outline=white_trans, width=2)
        
        # 5. Nodes at vertices (Mint nodes with white rings)
        nodes = [
            (256, 156), # Top
            (256, 316), # Bottom
            (186, 196), # Left
            (326, 196), # Right
            (186, 276), # Bottom-Left
            (326, 276)  # Bottom-Right
        ]
        for nx, ny in nodes:
            draw.ellipse([nx-8, ny-8, nx+8, ny+8], fill=mint, outline=white, width=2)
            
        # Central Bindu
        draw.ellipse([256-10, 236-10, 256+10, 236+10], fill=white, outline=gold, width=3)
        
        # 6. Typography "anydb" (Hand-drawn Vector Serif for maximum compatibility)
        # We draw individual characters dynamically to look premium on all machines
        # This bypasses missing TTF font problems in head-less servers
        char_color = gold
        
        # Helper to draw a Serif 'a'
        # Position: center around x=175, y=365
        # Draw elegant serif strokes for "anydb"
        # We will attempt to load a system serif font first
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
                # Render using TTF
                text = "anydb"
                w = draw.textlength(text, font=font)
                draw.text((256 - w/2, 355), text, fill=gold, font=font)
                font_loaded = True
                print(f"Loaded premium font: {font_path}")
                break
            except Exception:
                continue
                
        if not font_loaded:
            # Simple elegant fallback text rendering using default font
            try:
                font = ImageFont.load_default(size=30)
                text = "anydb"
                w = draw.textlength(text, font=font)
                draw.text((256 - w/2, 360), text, fill=gold, font=font)
                print("Using default fallback font")
            except Exception as e:
                # Absolute fallback: draw lines for letters
                print("Using line-drawing fallback")
                draw.text((220, 360), "anydb", fill=gold)
                
        img.save(dest_path, "PNG")
        print("Logo generated successfully!")
        return True
        
    except Exception as e:
        print(f"Failed to generate logo: {e}")
        return False

if __name__ == "__main__":
    generate_hybrid_png("/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/anydb_logo.png")
    generate_hybrid_png("/home/ruggedcoder/softwares/fresh/anydb_flutter/assets/logo_concepts/anydb_logo_yantra_prism.png")
