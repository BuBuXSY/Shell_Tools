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
