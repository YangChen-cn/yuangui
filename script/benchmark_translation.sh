#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
result_dir="$(mktemp -d "${TMPDIR:-/tmp}/yuangui-translation-benchmark.XXXXXX")"
result_log="$result_dir/test-output.log"
trap 'rm -rf "$result_dir"' EXIT

cd "$project_dir"
env \
  CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/yuangui-clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/yuangui-swiftpm-module-cache" \
  YUANGUI_TRANSLATION_BENCHMARK=1 \
  swift test --filter TranslationBenchmarkTests/testOfflineTranslationBenchmarkEmitsJSON \
  2>&1 | tee "$result_log" >&2

report="$(sed -n 's/^YUANGUI_BENCHMARK_JSON=//p' "$result_log" | tail -n 1)"
if [[ -z "$report" ]]; then
  print -u2 "未找到翻译性能 JSON 报告。"
  exit 1
fi

print -r -- "$report"
