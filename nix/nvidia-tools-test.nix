# NVIDIA's tools start: nvidia-smi and the others must get past the dynamic
# loader. The loader writes to each program's dynamic section at startup, so
# a build that leaves it on a page mapped read-only dies before main with
# SIGSEGV. Neither the driver nor a GPU is needed to see that.
{ pkgs, packages }:
pkgs.runCommand "sekka-nvidia-tools" { nativeBuildInputs = [ pkgs.binutils ]; } ''
  status=0
  for bin in ${pkgs.lib.concatStringsSep " " (pkgs.lib.unique (map (p: "${p.bin}/bin") packages))}; do
    for tool in "$bin"/*; do
      readelf -h "$tool" > /dev/null 2>&1 || continue
      # The dynamic section must lie inside a writable loadable segment and
      # share no page with a read-only one, which would be mapped over it.
      if ! readelf -lW "$tool" | awk '
        $1 == "LOAD" {
          n++; lo[n] = strtonum($3); hi[n] = lo[n] + strtonum($6)
          for (f = 7; f < NF; f++) if ($f ~ /W/) w[n] = 1
        }
        $1 == "DYNAMIC" { dyn = 1; d = strtonum($3); e = d + strtonum($6) }
        END {
          if (!dyn) exit 0
          page = 4096
          for (i = 1; i <= n; i++) {
            if (w[i] && lo[i] <= d && e <= hi[i]) inside = 1
            if (!w[i] && int(lo[i] / page) <= int((e - 1) / page) && int(d / page) <= int((hi[i] - 1) / page)) exit 1
          }
          exit !inside
        }
      '; then
        echo "$tool: dynamic section is not in a writable page" >&2
        status=1
      fi
    done
    # A program the loader can start prints its help without a driver.
    "$bin/nvidia-smi" --help > /dev/null || {
      echo "$bin/nvidia-smi: does not start (exit $?)" >&2
      status=1
    }
  done
  [ "$status" = 0 ] && touch "$out"
''
