"""Crée une archive zip dont les entrées portent des droits Unix.

Compress-Archive (Windows) n'enregistre pas le droit d'exécution : sous Linux, le binaire
décompressé ne se lançait pas sans « chmod +x ». Ici, chaque fichier est marqué comme créé
sous Unix (create_system = 3) avec le mode rw-r--r--, et ceux passés avec --exec en rwxr-xr-x.

Usage : python tools/make_zip.py archive.zip fichier1 fichier2 ... [--exec fichier1]
"""
import os
import sys
import zipfile


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    archive = argv[1]
    files: list[str] = []
    executables: set[str] = set()
    args = argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--exec" and i + 1 < len(args):
            executables.add(os.path.abspath(args[i + 1]))
            i += 2
            continue
        files.append(args[i])
        i += 1
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in files:
            info = zipfile.ZipInfo.from_file(f, arcname=os.path.basename(f))
            info.create_system = 3  # Unix : unzip applique alors les droits ci-dessous
            mode = 0o755 if os.path.abspath(f) in executables else 0o644
            info.external_attr = (0o100000 | mode) << 16  # Fichier ordinaire + droits
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(f, "rb") as src:
                z.writestr(info, src.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
