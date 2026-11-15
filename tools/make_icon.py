from PIL import Image
import sys
out = sys.argv[1]
N = 32
im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
px = im.load()
def put(x, y, c):
    if 0 <= x < N and 0 <= y < N:
        px[x, y] = c
# Ecu : bords droits puis pointe
def inside(x, y):
    if y < 3 or y > 29: return False
    if y <= 17: return 4 <= x <= 27
    t = (y - 17) / 12.0
    half = 12 * (1 - t ** 1.6)
    return abs(x + 0.5 - 16) <= half
DARK = (28, 22, 18, 255)
GOLD = (232, 184, 72, 255)
GOLD_D = (168, 120, 40, 255)
BLUE = (56, 97, 217, 255)
BLUE_D = (34, 62, 150, 255)
BLUE_L = (96, 136, 240, 255)
for y in range(N):
    for x in range(N):
        if inside(x, y):
            # bordure : voisin hors écu
            edge1 = any(not inside(x + dx, y + dy) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)))
            edge2 = any(not inside(x + dx, y + dy) for dx in (-2,-1,0,1,2) for dy in (-2,-1,0,1,2) if abs(dx)+abs(dy) <= 2)
            if edge1: put(x, y, DARK)
            elif edge2: put(x, y, GOLD if (x + y) % 7 else GOLD_D)
            else:
                c = BLUE
                if x < 16: c = BLUE_L if y < 8 else BLUE   # reflet à gauche en haut
                if x >= 16 and y > 12: c = BLUE_D
                put(x, y, c)
# Epées croisées (diagonales) : lame acier, garde et pommeau or
STEEL = (220, 224, 232, 255)
STEEL_D = (140, 146, 160, 255)
def sword(sx, sy, dx, length=11):
    # pointe en (sx, sy), lame en diagonale vers le bas
    for i in range(length):
        x = sx + dx * i; y = sy + i
        put(x, y, STEEL)
        put(x + dx, y, STEEL_D)
    gx, gy = sx + dx * length, sy + length
    for k in (-1, 0, 1):  # garde perpendiculaire à la lame
        put(gx + k, gy - k * dx, GOLD)
    put(gx + 2, gy - 2 * dx, GOLD_D); put(gx - 2, gy + 2 * dx, GOLD_D)  # bouts de garde
    put(gx + dx, gy + 1, (110, 70, 40, 255)); put(gx + 2 * dx, gy + 2, (110, 70, 40, 255))  # poignée
    put(gx + 3 * dx, gy + 3, GOLD); put(gx + 3 * dx + dx, gy + 3, GOLD_D)  # pommeau
sword(8, 7, 1)
sword(23, 7, -1)
# Ombre portée légère sous l'écu
im.save(out + ".png")
big = im.resize((256, 256), Image.NEAREST)
big.save(out + "_256.png")
im.resize((128, 128), Image.NEAREST).save(out + "_preview.png")
sizes = [(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)]
big.save(out + ".ico", sizes=sizes)
print("ok")
