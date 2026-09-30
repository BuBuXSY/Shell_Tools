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
    run "$REPO_ROOT/kernel_optimization.sh" --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"内核优化状态"* ]]

    run "$REPO_ROOT/kernel_optimization.sh" --scene baremetal --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"关键策略: NUMA"* ]]

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

@test "cleanup tool previews safely and rejects protected paths" {
    run "$REPO_ROOT/cleanup_junk.sh" --plan --paths "$BATS_TEST_TMPDIR" --days 30 --max-size 1M
    [ "$status" -eq 0 ]
    [[ "$output" == *"垃圾清理预览"* ]]
    run "$REPO_ROOT/cleanup_junk.sh" --plan --paths / --days 30 --max-size 1M
    [ "$status" -ne 0 ]
}

@test "cleanup applies file and byte limits to disposable test files" {
    temp_dir="$BATS_TEST_TMPDIR/junk"
    mkdir -p "$temp_dir"
    dd if=/dev/zero of="$temp_dir/one.cache" bs=1024 count=2 2>/dev/null
    dd if=/dev/zero of="$temp_dir/two.cache" bs=1024 count=2 2>/dev/null
    touch -t 202001010000 "$temp_dir/one.cache" "$temp_dir/two.cache"
    run "$REPO_ROOT/cleanup_junk.sh" --run --yes --paths "$temp_dir" --days 1 \
        --max-size 1 --max-total 2K --max-files 1
    [ "$status" -eq 0 ]
    [ "$(find "$temp_dir" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "cleanup cron rejects unsafe schedules" {
    run "$REPO_ROOT/cleanup_junk.sh" --install-cron --paths "$BATS_TEST_TMPDIR" \
        --schedule '0 3 * * *; touch /tmp/unsafe'
    [ "$status" -eq 2 ]
    [[ "$output" == *"cron 表达式"* ]]
}
