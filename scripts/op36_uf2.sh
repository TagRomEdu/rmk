#!/usr/bin/env bash

# Сборка OP36 и упаковка в UF2 для Adafruit nRF52 bootloader — то же, что CI делает
# через objcopy + uf2conv.py (--base 0x26000 --family 0xADA52840).
# Запуск из devShell: nix develop -c scripts/op36_uf2.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keyboard_dir="$repo_root/keyboards/op36"
release_dir="$keyboard_dir/target/thumbv7em-none-eabihf/release"
out_dir="$keyboard_dir/target/uf2"

for tool in cargo arm-none-eabi-objcopy perl; do
    command -v "$tool" >/dev/null || { echo "$tool not found, run inside nix develop" >&2; exit 1; }
done

(cd "$keyboard_dir" && cargo build --release --bin central --bin peripheral)

mkdir -p "$out_dir"

bin2uf2() {
    perl -e '
        my ($in, $out) = @ARGV;
        my ($base, $family) = (0x26000, 0xADA52840);
        open my $fh, "<:raw", $in or die "$in: $!";
        my $data = do { local $/; <$fh> };
        my $n = int((length($data) + 255) / 256);
        open my $o, ">:raw", $out or die "$out: $!";
        for my $i (0 .. $n - 1) {
            my $chunk = substr($data, $i * 256, 256);
            $chunk .= "\0" x (256 - length $chunk);
            print $o pack("V8", 0x0A324655, 0x9E5D5157, 0x2000, $base + $i * 256, 256, $i, $n, $family),
                $chunk, "\0" x 220, pack("V", 0x0AB16F30);
        }
    ' "$1" "$2"
}

for pair in central:left peripheral:right; do
    elf="$release_dir/${pair%%:*}"
    bin="$out_dir/${pair##*:}.bin"
    uf2="$out_dir/op36_${pair##*:}.uf2"
    arm-none-eabi-objcopy -O binary "$elf" "$bin"
    bin2uf2 "$bin" "$uf2"
    rm "$bin"
done

(cd "$out_dir" && sha256sum op36_left.uf2 op36_right.uf2)
echo "UF2: $out_dir"
