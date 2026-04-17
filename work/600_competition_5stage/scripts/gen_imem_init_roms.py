import argparse
from pathlib import Path


def parse_addr(text: str) -> int:
    return int(text, 0)


def parse_args():
    parser = argparse.ArgumentParser(description='Generate IMEM init txt and byte-lane txts from a binary image.')
    parser.add_argument('--bin', required=True, help='Input binary image path')
    parser.add_argument('--out-prefix', required=True, help='Output prefix without suffix')
    parser.add_argument('--start-addr', type=parse_addr, default=0, help='Load/start address of the binary image in IMEM space')
    return parser.parse_args()


def main():
    args = parse_args()
    bin_path = Path(args.bin)
    out_prefix = Path(args.out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    if args.start_addr < 0:
        raise ValueError('start address must be non-negative')
    if args.start_addr % 4 != 0:
        raise ValueError('start address must be 4-byte aligned')

    data = bin_path.read_bytes()
    pad_words = args.start_addr // 4
    word_count = (len(data) + 3) // 4

    word_lines = ['00000000'] * pad_words
    lane_lines = [['00' for _ in range(pad_words)] for _ in range(4)]

    for idx in range(word_count):
        chunk = data[idx * 4:(idx + 1) * 4]
        chunk = chunk + bytes(4 - len(chunk))
        b0, b1, b2, b3 = chunk[0], chunk[1], chunk[2], chunk[3]
        word_lines.append(f'{b3:02x}{b2:02x}{b1:02x}{b0:02x}')
        lane_lines[0].append(f'{b0:02x}')
        lane_lines[1].append(f'{b1:02x}')
        lane_lines[2].append(f'{b2:02x}')
        lane_lines[3].append(f'{b3:02x}')

    (out_prefix.with_suffix('.txt')).write_text('\n'.join(word_lines) + ('\n' if word_lines else ''))
    for lane_idx in range(4):
        (out_prefix.parent / f'{out_prefix.name}_b{lane_idx}.txt').write_text(
            '\n'.join(lane_lines[lane_idx]) + ('\n' if lane_lines[lane_idx] else '')
        )

    print(f'input bytes  = {len(data)}')
    print(f'start addr   = 0x{args.start_addr:08x}')
    print(f'pad words    = {pad_words}')
    print(f'output words = {len(word_lines)}')
    print(f'generated    = {out_prefix.with_suffix(".txt")}')
    for lane_idx in range(4):
        print(f'generated    = {out_prefix.parent / (out_prefix.name + f"_b{lane_idx}.txt")}')


if __name__ == '__main__':
    main()
