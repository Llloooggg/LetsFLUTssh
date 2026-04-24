#!/bin/bash -eu
# Build Dart fuzz targets for ClusterFuzzLite.
#
# ClusterFuzzLite expects binaries linked with libFuzzer (LLVMFuzzerTestOneInput).
# Dart can't link with libFuzzer directly, so we create a thin C harness that:
#   1. Receives fuzzer input from libFuzzer
#   2. Writes it to a temp file
#   3. Pipes it into the Dart native binary
#
# This gives us real fuzzing with coverage-guided mutation via libFuzzer,
# while the actual parsing logic runs in Dart.

# Compile Dart targets to native executables
for target in $SRC/letsflutssh/fuzz/fuzz_*.dart; do
  name=$(basename "$target" .dart)
  dart compile exe "$target" -o "$OUT/${name}_dart"
done

# Create C harness template that pipes libFuzzer input into a Dart binary
create_harness() {
  local name=$1
  local dart_bin="${name}_dart"

  cat > "/tmp/${name}.c" << HARNESS_EOF
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  // Write fuzz data to a pipe and feed it to the Dart binary's stdin
  int pipefd[2];
  if (pipe(pipefd) == -1) return 0;

  pid_t pid = fork();
  if (pid == -1) {
    close(pipefd[0]);
    close(pipefd[1]);
    return 0;
  }

  if (pid == 0) {
    // Child: run Dart binary with piped stdin
    close(pipefd[1]);
    dup2(pipefd[0], STDIN_FILENO);
    close(pipefd[0]);

    // Suppress stdout/stderr
    freopen("/dev/null", "w", stdout);
    freopen("/dev/null", "w", stderr);

    // Resolve path relative to this binary
    char self[4096];
    ssize_t len = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (len == -1) _exit(1);
    self[len] = '\0';

    // Replace binary name with dart binary name
    char *slash = strrchr(self, '/');
    if (slash) {
      strcpy(slash + 1, "${dart_bin}");
    }

    execl(self, self, NULL);
    _exit(1);
  }

  // Parent: write data and wait
  close(pipefd[0]);
  if (size > 0) {
    write(pipefd[1], data, size);
  }
  close(pipefd[1]);

  int status;
  waitpid(pid, &status, 0);
  return 0;
}
HARNESS_EOF

  $CC $CFLAGS -c "/tmp/${name}.c" -o "/tmp/${name}.o"
  $CXX $CXXFLAGS "/tmp/${name}.o" -o "$OUT/$name" $LIB_FUZZING_ENGINE
}

# Build harnesses for each Dart target
for dart_bin in "$OUT"/*_dart; do
  full_name=$(basename "$dart_bin")
  name=${full_name%_dart}
  create_harness "$name"

  # Create seed corpus
  mkdir -p "$OUT/${name}_seed_corpus"
done

# --- Seed corpora ---

cat > "$OUT/fuzz_json_parser_seed_corpus/valid_session.json" << 'SEED'
{"id":"abc-123","host":"example.com","port":22,"user":"root","auth_type":"password","label":"prod"}
SEED

cat > "$OUT/fuzz_json_parser_seed_corpus/valid_config.json" << 'SEED'
{"font_size":14,"theme":"dark","scrollback":5000,"keepalive_sec":30,"default_port":22}
SEED

cat > "$OUT/fuzz_json_parser_seed_corpus/valid_qr.json" << 'SEED'
{"v":1,"s":[{"l":"test","h":"example.com","u":"root","p":22}]}
SEED

cat > "$OUT/fuzz_json_parser_seed_corpus/empty.json" << 'SEED'
{}
SEED

cat > "$OUT/fuzz_known_hosts_seed_corpus/valid.txt" << 'SEED'
example.com:22 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ==
192.168.1.1:22 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI==
# comment line
SEED

cat > "$OUT/fuzz_uri_parser_seed_corpus/valid_connect.txt" << 'SEED'
letsflutssh://connect?host=example.com&user=root&port=22
SEED

cat > "$OUT/fuzz_uri_parser_seed_corpus/valid_import.txt" << 'SEED'
letsflutssh://import?d=eyJ2IjoxLCJzIjpbeyJsIjoidGVzdCIsImgiOiJob3N0IiwidSI6InVzZXIifV19
SEED

# KdfParams binary header — 10-byte blob: algo + memory (u32 BE) +
# iterations (u32 BE) + parallelism (u8). Seeds bracket every
# branch in _decode: accept path (defaults), zero-field rejection,
# and each cap-exceeded rejection. libFuzzer mutates from these
# anchors, so one seed per branch keeps the corpus tight against
# the real decision boundaries.
#   m = 46 MiB (0xb800 KiB), t = 2, p = 1 — production defaults.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/default.bin"
#   Unknown algo id — trips the first rejection branch.
printf '\xff\x00\x00\xb8\x00\x00\x00\x00\x02\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/algo_unknown.bin"
#   memory = 0 — trips the "params must be > 0" branch.
printf '\x01\x00\x00\x00\x00\x00\x00\x00\x02\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/mem_zero.bin"
#   iterations = 0.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x00\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/iter_zero.bin"
#   parallelism = 0.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x00' > \
  "$OUT/fuzz_kdf_params_seed_corpus/par_zero.bin"
#   memory = 1 GiB + 1 KiB (0x00100001) — one past the 1 GiB cap.
printf '\x01\x00\x10\x00\x01\x00\x00\x00\x02\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/mem_over_cap.bin"
#   iterations = 17 (0x11) — one past the 16-iter cap.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x11\x01' > \
  "$OUT/fuzz_kdf_params_seed_corpus/iter_over_cap.bin"
#   parallelism = 9 — one past the 8-lane cap.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x09' > \
  "$OUT/fuzz_kdf_params_seed_corpus/par_over_cap.bin"
#   9-byte truncated header — trips the length check after algo.
printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02' > \
  "$OUT/fuzz_kdf_params_seed_corpus/truncated.bin"

# LFS archive header — LFSE magic + version 0x02 + KDF blob +
# 32-byte salt + 12-byte IV. Seeds bracket every branch in
# _parseHeader: accept path, bad magic, bad version, each KDF cap
# rejection, and truncated-payload rejection. Salt/IV are zero
# bytes on purpose — seeds must be deterministic so the corpus
# reproduces across CI runs.
{
  printf 'LFSE\x02'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/default.bin"
# Bad magic — trips the magic-byte loop.
{
  printf 'AAAA\x02'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/bad_magic.bin"
# Unsupported version — trips the version gate.
{
  printf 'LFSE\x03'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/bad_version.bin"
# KDF memory > 1 GiB cap.
{
  printf 'LFSE\x02'
  printf '\x01\x00\x10\x00\x01\x00\x00\x00\x02\x01'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/kdf_mem_over.bin"
# KDF iterations = 21 (one past the 20-iter cap).
{
  printf 'LFSE\x02'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x15\x01'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/kdf_iter_over.bin"
# KDF parallelism = 17 (one past the 16-lane cap).
{
  printf 'LFSE\x02'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x11'
  printf '%.0s\x00' {1..44}
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/kdf_par_over.bin"
# Truncated — magic + version + KDF blob only, no salt/IV room.
# Trips the final length check for salt + iv.
{
  printf 'LFSE\x02'
  printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01'
} > "$OUT/fuzz_lfs_archive_header_seed_corpus/truncated.bin"
