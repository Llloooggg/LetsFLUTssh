#!/bin/bash -eu
# Build Dart fuzz targets as native executables for ClusterFuzzLite / AFL++.
#
# Each fuzz target reads from stdin and exercises parsing logic.
# Compiled to native code via `dart compile exe`.

for target in $SRC/letsflutssh/fuzz/fuzz_*.dart; do
  name=$(basename "$target" .dart)
  dart compile exe "$target" -o "$OUT/$name"

  # Create a minimal seed corpus for each target
  mkdir -p "$OUT/${name}_seed_corpus"
done

# --- Seed corpora ---

# fuzz_json_parser: valid and edge-case JSON inputs
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

# fuzz_known_hosts: valid and edge-case known_hosts entries
cat > "$OUT/fuzz_known_hosts_seed_corpus/valid.txt" << 'SEED'
example.com:22 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ==
192.168.1.1:22 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI==
# comment line
SEED

cat > "$OUT/fuzz_known_hosts_seed_corpus/edge.txt" << 'SEED'
host:0 type data extra fields
:22 ssh-rsa key
host:-1 ssh-rsa key
SEED

# fuzz_uri_parser: valid and edge-case URIs
cat > "$OUT/fuzz_uri_parser_seed_corpus/valid_connect.txt" << 'SEED'
letsflutssh://connect?host=example.com&user=root&port=22
SEED

cat > "$OUT/fuzz_uri_parser_seed_corpus/valid_import.txt" << 'SEED'
letsflutssh://import?d=eyJ2IjoxLCJzIjpbeyJsIjoidGVzdCIsImgiOiJob3N0IiwidSI6InVzZXIifV19
SEED

cat > "$OUT/fuzz_uri_parser_seed_corpus/edge.txt" << 'SEED'
letsflutssh://connect?host=&user=&port=0
SEED
