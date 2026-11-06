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

@test "Nginx build root override uses the selected filesystem" {
    run env NGINX_BUILD_ROOT="$BATS_TEST_TMPDIR" bash -c '
        source "$1"
        df() {
            printf "Filesystem 1048576-blocks Used Available Capacity Mounted on\nroot 10000 1000 9000 10%% /\n"
        }
        select_build_root
        [[ "$BUILD_ROOT_SELECTED" == "$NGINX_BUILD_ROOT" && "$BUILD_ROOT_FREE_MB" == 9000 ]]
    ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh"
    [ "$status" -eq 0 ]
}

@test "Nginx build root override reports insufficient space" {
    run env NGINX_BUILD_ROOT="$BATS_TEST_TMPDIR" bash -c '
        source "$1"
        df() { printf "Filesystem 1048576-blocks Used Available Capacity Mounted on\ntmpfs 966 0 966 0%% /tmp\n"; }
        select_build_root
    ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"${BATS_TEST_TMPDIR}: 966MB"* ]]
}

# Include single-byte and legacy multibyte locales when installed: UTF-8
# punctuation next to an unbraced variable can be parsed as part of its name.
nginx_test_locales() {
    printf '%s\n' C
    locale -a 2>/dev/null | LC_ALL=C grep -Ei '^(C[.](utf-8|utf8)|en_US[.](iso8859-1|iso88591)|zh_CN[.]gbk)$' || true
}

@test "Nginx preflight handles localized messages under available locales" {
    [ "$EUID" -eq 0 ] || skip "preflight requires root"
    local test_locale
    while IFS= read -r test_locale; do
        run env LC_ALL="$test_locale" NGINX_BUILD_ROOT="$BATS_TEST_TMPDIR" bash -c '
            source "$1"
            LOG_FILE="$2/preflight.log"
            configure_network_proxy() { :; }
            df() { printf "Filesystem 1048576-blocks Used Available Capacity Mounted on\nroot 10000 1000 9000 10%% /\n"; }
            preflight
            [[ -d "$BUILD_DIR" && "$(stat -c %a "$BUILD_DIR")" == 700 ]]
        ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh" "$BATS_TEST_TMPDIR"
        [ "$status" -eq 0 ]
        [[ "$output" == *"前置检查完成"* ]]
        [[ "$output" == *"（可用 9000MB）"* ]]
        [[ "$output" != *"unbound variable"* ]]
        [ -z "$(find "$BATS_TEST_TMPDIR" -name 'nginx-build.*' -print)" ]
    done < <(nginx_test_locales)
}

@test "Nginx failed exit cleans workspace and prints diagnostics under available locales" {
    local test_locale
    while IFS= read -r test_locale; do
        run env LC_ALL="$test_locale" bash -c '
            source "$1"
            LOG_FILE="$2/install.log"
            RUN_STARTED=1
            BUILD_DIR=$(mktemp -d "$2/nginx-build.XXXXXX")
            exit 37
        ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh" "$BATS_TEST_TMPDIR"
        [ "$status" -eq 37 ]
        [[ "$output" == *"安装失败（退出码: 37），诊断建议："* ]]
        [[ "$output" == *"检查磁盘空间"* ]]
        [[ "$output" != *"unbound variable"* ]]
        [ -z "$(find "$BATS_TEST_TMPDIR" -name 'nginx-build.*' -print)" ]
    done < <(nginx_test_locales)
}

@test "Nginx version lookup failure returns an error" {
    run bash -c '
        source "$1"
        curl() { return 7; }
        get_nginx_version mainline >/dev/null
    ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"无法获取版本列表"* ]]
}

@test "Nginx version lookup rejects partial timeout responses" {
    run bash -c '
        source "$1"
        BUILD_DIR="$2"
        curl() {
            local output=""
            while [[ "$#" -gt 0 ]]; do
                [[ "$1" == "-o" ]] && output="$2"
                shift
            done
            printf "%s" "nginx-1.10.1.tar.gz" > "$output"
            return 28
        }
        get_nginx_version mainline >/dev/null
    ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"无法获取版本列表"* ]]
}

@test "Nginx network check follows curl proxy path" {
    run bash -c '
        source "$1"
        curl() { [[ "$*" == *"nginx.org/download"* ]] && return 0; return 1; }
        check_network
    ' bash "$REPO_ROOT/Auto_Upgrade_Nginx.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"https://nginx.org/download/"* ]]
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
