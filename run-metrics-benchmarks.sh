#!/usr/bin/env bash
set -e

echo "Building all targets ..."
build_dir_tracing_off=/tmp/build_dir_tracing_off
mkdir -p "$build_dir_tracing_off"
cmake -B "$build_dir_tracing_off" -S . \
  -D CMAKE_BUILD_TYPE=Release \
  -D TRACING_ENABLED=OFF
cmake --build "$build_dir_tracing_off" --target all --
build_dir_opentelemetry_off=/tmp/build_dir_opentelemetry_off
mkdir -p "$build_dir_opentelemetry_off"
cmake -B "$build_dir_opentelemetry_off" -S . \
  -D CMAKE_BUILD_TYPE=Release \
  -D TRACING_ENABLED=ON \
  -D OPENTELEMETRY_C_TRACING_ENABLED=OFF
cmake --build "$build_dir_opentelemetry_off" --target all --
build_dir_lttng_exporter_on=/tmp/build_dir_lttng_exporter_on
mkdir -p "$build_dir_lttng_exporter_on"
cmake -B "$build_dir_lttng_exporter_on" -S . \
  -D CMAKE_BUILD_TYPE=Release \
  -D TRACING_ENABLED=ON \
  -D OPENTELEMETRY_C_TRACING_ENABLED=ON \
  -D LTTNG_EXPORTER_ENABLED=ON
cmake --build "$build_dir_lttng_exporter_on" --target all --
build_dir_lttng_exporter_off=/tmp/build_dir_lttng_exporter_off
mkdir -p "$build_dir_lttng_exporter_off"
cmake -B "$build_dir_lttng_exporter_off" -S . \
  -D CMAKE_BUILD_TYPE=Release \
  -D TRACING_ENABLED=ON \
  -D OPENTELEMETRY_C_TRACING_ENABLED=ON \
  -D LTTNG_EXPORTER_ENABLED=OFF
cmake --build "$build_dir_lttng_exporter_off" --target all --

n=10 # n = number of run per executable

all_executables=(
  "benchmark-metrics-observable-up-down-counter-500"
  "benchmark-metrics-observable-up-down-counter-1000"
)
for executable in "${all_executables[@]}"; do

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=OFF ##########"
    "$build_dir_tracing_off/$executable"
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=OFF without lttng session ##########"
    "$build_dir_opentelemetry_off/$executable"
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=OFF in lttng session but all events disabled ##########"
    lttng create
    lttng enable-channel --userspace default-channel
    lttng start
    "$build_dir_opentelemetry_off/$executable"
    lttng stop
    lttng destroy
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=OFF in lttng session ust event enabled ##########"
    lttng create "--output=ctf-traces/$executable/open-telemetry-off"
    lttng enable-event -u 'opentelemetry:*'
    lttng start
    "$build_dir_opentelemetry_off/$executable"
    lttng stop
    lttng destroy
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=ON LTTNG_EXPORTER_ENABLED=OFF with local collector ##########"
    "$build_dir_lttng_exporter_off/$executable"
  done

  # Run benchmark with remote collector only if available
  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=ON LTTNG_EXPORTER_ENABLED=OFF with remote collector ##########"
    if curl http://otel-collector-vm.aka.fyty.app:13133/ | grep -q "Server available"; then
      OTEL_EXPORTER_OTLP_METRICS_ENDPOINT="http://otel-collector-vm.aka.fyty.app:4317" "$build_dir_lttng_exporter_off/$executable"
    else
      echo "Remote collector not responding"
    fi
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=ON LTTNG_EXPORTER_ENABLED=ON without lttng session ##########"
    "$build_dir_lttng_exporter_on/$executable"
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=ON LTTNG_EXPORTER_ENABLED=ON in lttng session but all events disabled ##########"
    lttng create
    lttng enable-channel --userspace default-channel
    lttng start
    "$build_dir_lttng_exporter_on/$executable"
    lttng stop
    lttng destroy
  done

  for i in $(seq 1 $n); do
    echo "########## Run no $i executable=$executable TRACING_ENABLED=ON OPENTELEMETRY_C_TRACING_ENABLED=ON LTTNG_EXPORTER_ENABLED=ON in lttng session ust event enabled ##########"
    lttng create
    lttng enable-event -u 'opentelemetry:*'
    lttng start
    "$build_dir_lttng_exporter_on/$executable"
    lttng stop
    lttng destroy
  done

done

echo "Done!"
