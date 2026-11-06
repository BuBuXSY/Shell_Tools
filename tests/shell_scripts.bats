#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

shell_test_locales() {
    printf '%s\n' C
    locale -a 2>/dev/null | LC_ALL=C grep -Ei '^(C[.](utf-8|utf8)|en_US[.](iso8859-1|iso88591)|zh_CN[.]gbk)$' || true
}

@test "every shell tool provides a successful help path" {
    local script test_locale
    while IFS= read -r test_locale; do
        for script in "$REPO_ROOT"/*.sh; do
            run env LC_ALL="$test_locale" timeout 5s "$script" --help
            if [ "$status" -ne 0 ]; then
                printf 'help failed: %s locale=%s status=%s output=%s\n' "$script" "$test_locale" "$status" "$output" >&2
            fi
            [ "$status" -eq 0 ]
        done
    done < <(shell_test_locales)
}

@test "IP report uses cached locations without network under available locales" {
    printf '%s\n' '192.0.2.1 dns.example GET / 200' > "$BATS_TEST_TMPDIR/access.log"
    printf '192.0.2.1\t测试位置\n' > "$BATS_TEST_TMPDIR/cache"
    local test_locale
    while IFS= read -r test_locale; do
        run env LC_ALL="$test_locale" "$REPO_ROOT/search_ip.sh" \
            --log-file "$BATS_TEST_TMPDIR/access.log" --cache-file "$BATS_TEST_TMPDIR/cache" --no-push
        [ "$status" -eq 0 ]
        [[ "$output" == *"频次: 1 位置: 测试位置"* ]]
        [[ "$output" == *"已选择仅输出本地报告"* ]]
    done < <(shell_test_locales)
}

@test "DNS invalid log size preserves the diagnostic under available locales" {
    printf '%s\n' "DOMAIN_FILE=/dev/null" "OUTPUT_FILE=$BATS_TEST_TMPDIR/out" \
        "LOG_FILE=$BATS_TEST_TMPDIR/dns.log" "LOCK_FILE=$BATS_TEST_TMPDIR/lock" \
        'MAX_LOG_SIZE=invalid' 'ENABLE_HISTORY=false' > "$BATS_TEST_TMPDIR/dns.conf"
    local test_locale
    while IFS= read -r test_locale; do
        run env LC_ALL="$test_locale" "$REPO_ROOT/collect_repeat_dns.sh" --config "$BATS_TEST_TMPDIR/dns.conf"
        [ "$status" -eq 1 ]
        [[ "$output" == *"MAX_LOG_SIZE 格式无效: invalid（示例: 100M、1G）"* ]]
        [[ "$output" != *"unbound variable"* ]]
    done < <(shell_test_locales)
}

@test "invalid arguments return the documented usage status" {
    run "$REPO_ROOT/kernel_optimization.sh" --scene not-a-scene
    [ "$status" -eq 2 ] || printf 'kernel invalid scene status=%s output=%s\n' "$status" "$output" >&2
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
    [ "$status" -eq 2 ] || printf 'doh invalid format status=%s output=%s\n' "$status" "$output" >&2
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
    run env LOG_FILE="$tmp/access.log" WEBHOOK_URL="http://127.0.0.1/hook" "$REPO_ROOT/nginx_access_analyzer.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"必须使用 https"* ]]
}

@test "remote TLS and DoH endpoint reject unsafe inputs without network access" {
    run "$REPO_ROOT/ssl_cert_monitor.sh" --remote-host example.invalid --remote-port 0
    [ "$status" -eq 2 ]
    run "$REPO_ROOT/enhanced-doh-test.sh" --endpoint http://127.0.0.1/dns-query
    [ "$status" -eq 2 ]
    run "$REPO_ROOT/enhanced-doh-test.sh" --max-concurrency 33
    [ "$status" -eq 2 ]
}

@test "nginx time window and bucket settings reject invalid values" {
    tmp="$BATS_TEST_TMPDIR/access.log"; : > "$tmp"
    run env LOG_FILE="$tmp" WINDOW_MINUTES=abc "$REPO_ROOT/nginx_access_analyzer.sh"
    [ "$status" -eq 2 ]
    run env LOG_FILE="$tmp" BUCKET_MINUTES=-1 "$REPO_ROOT/nginx_access_analyzer.sh"
    [ "$status" -eq 2 ]
}
