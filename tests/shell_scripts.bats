#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "every shell tool provides a successful help path" {
    local script
    for script in "$REPO_ROOT"/*.sh; do
        run timeout 5s "$script" --help
        [ "$status" -eq 0 ]
    done
}

@test "invalid arguments return the documented usage status" {
    run "$REPO_ROOT/kernel_optimization.sh" --scene not-a-scene
    [ "$status" -eq 2 ]
    [[ "$output" == *"无效场景"* ]]

    run env KEEP_DAYS=not-a-number "$REPO_ROOT/system_config_backup.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"KEEP_DAYS"* ]]

    run "$REPO_ROOT/update_frp.sh" --action unsupported
    [ "$status" -eq 2 ]
    [[ "$output" == *"无效操作"* ]]

    run "$REPO_ROOT/update_Country.sh" --unsupported
    [ "$status" -eq 2 ]
    [[ "$output" == *"未知参数"* ]]
}

@test "read-only report options reject invalid local configuration before work starts" {
    run "$REPO_ROOT/server_status_report.sh" --cache-timeout 0 --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"缓存有效期"* ]]

    run "$REPO_ROOT/enhanced-doh-test.sh" --format unsupported
    [ "$status" -eq 2 ]
    [[ "$output" == *"无效输出格式"* ]]
}

@test "collect_repeat_dns rejects executable config and accepts safe config" {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    printf '%s\n' 'DOMAIN_FILE=/dev/null' 'OUTPUT_FILE=/tmp/out' 'THRESHOLD=3' '$(touch "$tmp/pwned")' > "$tmp/bad.conf"
    run "$REPO_ROOT/collect_repeat_dns.sh" --config "$tmp/bad.conf"
    [ "$status" -ne 0 ]
    [ ! -e "$tmp/pwned" ]
    printf '%s\n' 'DOMAIN_FILE=/dev/null' "OUTPUT_FILE=$tmp/out" 'THRESHOLD=3' 'ENABLE_HISTORY=false' 'ENABLE_STATS=false' > "$tmp/good.conf"
    run env DNS_MONITOR_LOCK_FILE="$tmp/lock" "$REPO_ROOT/collect_repeat_dns.sh" --config "$tmp/good.conf"
    [ "$status" -eq 0 ]
}

@test "webhook options reject HTTP without making a request" {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    printf '%s\n' '127.0.0.1 dns.example GET / 200' > "$tmp/access.log"
    run env NGINX_LOG_FILE="$tmp/access.log" WEBHOOK_URL="http://127.0.0.1/hook" "$REPO_ROOT/nginx_access_analyzer.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"必须使用 https"* ]]
}
