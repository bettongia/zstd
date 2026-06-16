# Stage 1: build addlicense (Go tool used by the license_check target)
FROM docker.io/library/golang:latest AS addlicense-builder
RUN CGO_ENABLED=0 go install github.com/google/addlicense@latest

# Stage 2: Dart runtime with ICU and tooling
FROM docker.io/library/dart:stable

COPY --from=addlicense-builder /go/bin/addlicense /usr/local/bin/addlicense

RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    clang libclang-dev \
    lcov \
    chromium \
    git \
    python3 \
    xz-utils \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Install Emscripten SDK at the pinned version (EMSCRIPTEN_VERSION file at repo root)
COPY EMSCRIPTEN_VERSION /tmp/EMSCRIPTEN_VERSION
ENV EMSDK=/emsdk
RUN git clone https://github.com/emscripten-core/emsdk.git $EMSDK && \
    version=$(cat /tmp/EMSCRIPTEN_VERSION) && \
    $EMSDK/emsdk install "$version" && \
    $EMSDK/emsdk activate "$version" --embedded
ENV PATH="/emsdk/upstream/emscripten:${PATH}"

RUN useradd --create-home --shell /bin/sh runner

ENV HOME=/home/runner
ENV CHROME_EXECUTABLE=chromium

# dart pub global activate installs binaries here (e.g. coverage's format_coverage)
ENV PATH="/home/runner/.pub-cache/bin:${PATH}"

USER runner
WORKDIR /home/runner/app

COPY --chown=runner:runner . .

CMD ["make", "container-cicd"]
