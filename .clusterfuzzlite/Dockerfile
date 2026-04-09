FROM gcr.io/oss-fuzz-base/base-builder

# Install Dart SDK via zip (apt repo URL is unreliable)
ARG DART_VERSION=3.7.2
RUN curl -fsSL "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-x64-release.zip" \
      -o /tmp/dart-sdk.zip && \
    unzip -q /tmp/dart-sdk.zip -d /opt && \
    rm /tmp/dart-sdk.zip

ENV PATH="/opt/dart-sdk/bin:${PATH}"

COPY . $SRC/letsflutssh
WORKDIR $SRC/letsflutssh

COPY .clusterfuzzlite/build.sh $SRC/build.sh
