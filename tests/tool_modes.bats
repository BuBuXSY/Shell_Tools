#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "mutating tools expose read-only plans" {
    run "$REPO_ROOT/Auto_Upgrade_Nginx.sh" --channel stable --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nginx 升级预览"* ]]

    run "$REPO_ROOT/kernel_optimization.sh" --scene vps --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"内核优化预览"* ]]

    run "$REPO_ROOT/install_cert.sh" --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSL 证书部署预览"* ]]

    run "$REPO_ROOT/system_config_backup.sh" --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"配置备份预览"* ]]

    run "$REPO_ROOT/update_frp.sh" --action install --role frpc --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"FRP 操作预览"* ]]
}

@test "DNS plan validates configuration without creating files" {
    config="$BATS_TEST_TMPDIR/missing.conf"
    run env DNS_MONITOR_CONFIG="$config" DNS_MONITOR_CREATE_CONFIG=true "$REPO_ROOT/collect_repeat_dns.sh" --plan
    [ "$status" -eq 0 ]
    [ ! -e "$config" ]
    [[ "$output" == *"DNS 重复查询分析预览"* ]]
}

@test "analysis tools reject invalid direct parameters" {
    run "$REPO_ROOT/disk_usage_analyzer.sh" --target "$BATS_TEST_TMPDIR" --top 0
    [ "$status" -eq 2 ]
    run "$REPO_ROOT/search_ip.sh" --top zero --no-push
    [ "$status" -eq 2 ]
    : > "$BATS_TEST_TMPDIR/access.log"
    run "$REPO_ROOT/nginx_access_analyzer.sh" --log-file "$BATS_TEST_TMPDIR/access.log" --top 0
    [ "$status" -eq 2 ]
}

@test "interactive modes require a terminal" {
    local script
    for script in disk_usage_analyzer.sh enhanced-doh-test.sh nginx_access_analyzer.sh \
        search_ip.sh server_security_audit.sh server_status_report.sh \
        ssl_cert_monitor.sh system_health_snapshot.sh; do
        run "$REPO_ROOT/$script" --interactive
        [ "$status" -eq 2 ]
    done
}

@test "platform probe emits parseable JSON" {
    run "$REPO_ROOT/platform_check.sh" --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | node -e 'let input="";process.stdin.on("data",x=>input+=x);process.stdin.on("end",()=>{const data=JSON.parse(input);if(!data.os||!data.arch)process.exit(1)})'
}
