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
