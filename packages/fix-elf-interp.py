#!/usr/bin/env python3
"""Fix PT_INTERP segment in a broken ELF binary where p_offset and p_filesz are 0
but the interpreter string exists at the correct virtual address."""
import struct, sys

def fix_interp(binary_path):
    with open(binary_path, 'r+b') as f:
        # Read ELF header
        ident = f.read(16)
        if ident[:4] != b'\x7fELF':
            print("Not an ELF file", file=sys.stderr)
            return False
        
        is_64 = ident[4] == 2
        is_le = ident[5] == 1
        
        endian = '<' if is_le else '>'
        
        if is_64:
            # Read e_phoff (offset 32, 8 bytes)
            f.seek(32)
            e_phoff = struct.unpack(endian + 'Q', f.read(8))[0]
            # e_phentsize (offset 54, 2 bytes)
            f.seek(54)
            e_phentsize = struct.unpack(endian + 'H', f.read(2))[0]
            # e_phnum (offset 56, 2 bytes)
            e_phnum = struct.unpack(endian + 'H', f.read(2))[0]
            
            phdr_fmt = endian + 'IIQQQQQQ'  # p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align
            phdr_size = 56  # 64-bit phdr
            
            for i in range(e_phnum):
                offset = e_phoff + i * phdr_size
                f.seek(offset)
                data = f.read(phdr_size)
                p_type = struct.unpack(endian + 'I', data[:4])[0]
                
                if p_type == 3:  # PT_INTERP
                    p_flags, p_offset_val, p_vaddr, p_paddr, p_filesz, p_memsz = struct.unpack(endian + 'IQQQQQ', data[4:])
                    print(f"Found PT_INTERP: p_offset={hex(p_offset_val)}, p_vaddr={hex(p_vaddr)}, p_filesz={p_filesz}, p_memsz={p_memsz}")
                    
                    # The interpreter string should be at file offset = p_vaddr (since LOAD maps offset 0 to VA 0)
                    # But actually we need the correct file offset. For the first LOAD, offset=0, VA=0
                    # So file_offset = p_vaddr
                    f.seek(p_vaddr)
                    interp = f.read(256).split(b'\x00')[0]
                    print(f"Interpreter: {interp.decode()}")
                    
                    # Calculate correct file offset: equal to p_vaddr since first LOAD has offset=0, VA=0
                    correct_offset = p_vaddr
                    correct_size = len(interp) + 1  # include null terminator
                    
                    # Patch p_offset (bytes 4-11 of phdr, after p_type)
                    f.seek(offset + 4 + 4)  # skip p_type (4) + p_flags (4)
                    f.write(struct.pack(endian + 'Q', correct_offset))
                    
                    # Patch p_filesz (bytes 24-31 of phdr, after p_paddr)
                    f.seek(offset + 4 + 4 + 8 + 8 + 8)  # p_type + p_flags + p_offset + p_vaddr + p_paddr
                    f.write(struct.pack(endian + 'Q', correct_size))
                    
                    # Patch p_memsz (bytes 32-39)
                    f.write(struct.pack(endian + 'Q', correct_size))
                    
                    print(f"Patched: p_offset={hex(correct_offset)}, p_filesz={correct_size}, p_memsz={correct_size}")
                    return True
            
            print("PT_INTERP not found", file=sys.stderr)
            return False
        else:
            print("32-bit ELF not supported", file=sys.stderr)
            return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix-elf-interp.py <binary>", file=sys.stderr)
        sys.exit(1)
    
    success = fix_interp(sys.argv[1])
    sys.exit(0 if success else 1)
