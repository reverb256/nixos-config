{
  lib,
  stdenv,
  fetchurl,
  python3,
  version ? "3.4.1",
}: let
  src = fetchurl {
    url = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${version}/SRBMiner-Multi-${builtins.replaceStrings ["."] ["-"] version}-Linux.tar.gz";
    hash = "sha256-wt5tqHr61tU2VzCEpGz7COK9WzjNv5JFGZ0JOm6mlw8=";
  };
in
  stdenv.mkDerivation {
    pname = "srbminer-multi";
    inherit version src;

    nativeBuildInputs = [python3];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      mkdir -p $out/bin
      tar -xzf $src
      if [ -f SRBMiner-MULTI ]; then
        mv SRBMiner-MULTI $out/bin/
      else
        mv SRBMiner-Multi-*/SRBMiner-MULTI $out/bin/
      fi
      chmod +x $out/bin/SRBMiner-MULTI
    '';

    postFixup = ''
      python3 -c "
import struct
with open('$out/bin/SRBMiner-MULTI', 'r+b') as f:
    f.seek(32)
    e_phoff = struct.unpack('<Q', f.read(8))[0]
    f.seek(56)
    e_phnum = struct.unpack('<H', f.read(2))[0]
    for i in range(e_phnum):
        off = e_phoff + i * 56
        f.seek(off)
        p_type = struct.unpack('<I', f.read(4))[0]
        if p_type == 3:
            f.seek(off + 8)
            p_off, p_vaddr = struct.unpack('<QQ', f.read(16))[:2]
            if p_off == 0:
                f.seek(p_vaddr)
                interp = f.read(256).split(b'\x00')[0]
                correct_off = p_vaddr
                correct_sz = len(interp) + 1
                f.seek(off + 8)
                f.write(struct.pack('<Q', correct_off))
                f.seek(off + 24)
                f.write(struct.pack('<Q', correct_sz))
                f.write(struct.pack('<Q', correct_sz))
                print(f'Fixed PT_INTERP: {interp.decode()}')
            else:
                print(f'PT_INTERP OK, offset={hex(p_off)}')
            break
"
    '';

    meta = {
      description = "SRBMiner-Multi - GPU/CPU miner for various algorithms";
      homepage = "https://github.com/doktor83/SRBMiner-Multi";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      maintainers = [];
    };
  }
