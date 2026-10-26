# ResQ Dispatch backend - Linux container (used by Render, Railway, or any Docker host)

# ---- build stage ----
FROM ubuntu:24.04 AS build
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates libsqlite3-dev libasio-dev \
    && rm -rf /var/lib/apt/lists/*

# Crow (header-only HTTP framework)
RUN git clone --depth 1 --branch v1.2.0 https://github.com/CrowCpp/Crow.git /tmp/crow \
    && cmake -S /tmp/crow -B /tmp/crow/build -DCROW_BUILD_EXAMPLES=OFF -DCROW_BUILD_TESTS=OFF \
    && cmake --install /tmp/crow/build

WORKDIR /src
COPY CMakeLists.txt ./
COPY src ./src
COPY tests ./tests
COPY db ./db
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DRESQ_BUILD_TESTS=ON \
    && cmake --build build -j"$(nproc)" \
    && cd build && ctest --output-on-failure

# ---- runtime stage ----
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/build/resq_server /app/resq_server
COPY db ./db
COPY public ./public
RUN mkdir -p /app/data

ENV RESQ_ROOT=/app \
    RESQ_BIND=0.0.0.0 \
    RESQ_DB=/app/data/resq.db \
    PORT=8080
EXPOSE 8080
CMD ["/app/resq_server"]
