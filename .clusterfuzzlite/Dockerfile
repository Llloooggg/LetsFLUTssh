FROM gcr.io/oss-fuzz-base/base-builder

# Install Dart SDK
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates gnupg curl unzip && \
    curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/dart-archive-keyring.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/dart-archive-keyring.gpg] https://storage.googleapis.com/dart-archive/channels/stable/release/latest/linux/debian stable main' \
      > /etc/apt/sources.list.d/dart.list && \
    apt-get update && apt-get install -y dart && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/dart/bin:${PATH}"

COPY . $SRC/letsflutssh
WORKDIR $SRC/letsflutssh

COPY .clusterfuzzlite/build.sh $SRC/build.sh
