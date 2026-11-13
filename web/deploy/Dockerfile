# The brokenbench runner: Verilator built from a pinned release, z3 for
# randomization, and this repo. Build from the repo root:
#   docker build -f web/deploy/Dockerfile -t brokenbench-runner .
FROM ubuntu:24.04 AS verilator
ARG VERILATOR_TAG=v5.054
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates git autoconf bison flex g++ make perl python3 help2man libfl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$VERILATOR_TAG" https://github.com/verilator/verilator /src \
    && cd /src && autoconf && ./configure --prefix=/opt/verilator \
    && make -j"$(nproc)" && make install && rm -rf /src

FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      g++ make perl python3 z3 libfl2 zlib1g \
    && rm -rf /var/lib/apt/lists/*
COPY --from=verilator /opt/verilator /opt/verilator
ENV PATH=/opt/verilator/bin:$PATH TMPDIR=/work
RUN useradd --system --home /nonexistent runner && mkdir /work && chown runner /work
COPY manifest.toml /bb/
COPY scripts /bb/scripts
COPY exercises /bb/exercises
COPY learn /bb/learn
COPY vendor /bb/vendor
COPY web/runner.py /bb/web/
USER runner
WORKDIR /bb
EXPOSE 8787
ENTRYPOINT ["python3", "web/runner.py", "--host", "0.0.0.0"]
