#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "toolbox lists every shell tool without executing it" {
    run "$REPO_ROOT/shell_tools.sh" --list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 23 ]
    [[ "$output" == *"install_cert.sh"* ]]
    [[ "$output" == *"system_health_snapshot.sh"* ]]
    [[ "$output" == *"platform_check.sh"* ]]
    [[ "$output" == *"cleanup_junk.sh"* ]]
    [[ "$output" == *"server_benchmark.sh"* ]]
}

@test "toolbox dashboard supports text and JSON output" {
    run "$REPO_ROOT/shell_tools.sh" --dashboard
    [ "$status" -eq 0 ]
    [[ "$output" == *"Shell_Tools 超级运维控制台"* ]]
    run "$REPO_ROOT/shell_tools.sh" --dashboard --format json
    [ "$status" -eq 0 ]
    node -e 'const v=JSON.parse(process.argv[1]); if(typeof v.health_score!=="number"||!v.kernel)process.exit(1)' "$output"
    run "$REPO_ROOT/shell_tools.sh" --dashboard --format markdown
    [ "$status" -eq 0 ]
    [[ "$output" == *"| 指标 | 当前值 |"* ]]
    run "$REPO_ROOT/shell_tools.sh" --watch 2
    [ "$status" -eq 2 ]
}

@test "network diagnostics expose structured read-only output" {
    run "$REPO_ROOT/router_diagnostics.sh" --format json
    [ "$status" -eq 0 ]
    node -e 'const v=JSON.parse(process.argv[1]); if(!v.severity||!v.recommendation)process.exit(1)' "$output"
    run "$REPO_ROOT/remote_inspection.sh" --host invalid.example --format json --plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"远程巡检预览"* ]]
}

@test "toolbox rejects unregistered scripts" {
    run "$REPO_ROOT/shell_tools.sh" --run ../install_cert.sh
    [ "$status" -eq 2 ]
    [[ "$output" == *"未知脚本"* ]]
}

@test "toolbox forwards arguments to a registered script" {
    run "$REPO_ROOT/shell_tools.sh" --run system_health_snapshot.sh -- --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--format"* ]]
}

@test "toolbox refuses interactive mode without a terminal" {
    run "$REPO_ROOT/shell_tools.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"需要终端"* ]]
}
