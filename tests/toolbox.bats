#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "toolbox lists every shell tool without executing it" {
    run "$REPO_ROOT/shell_tools.sh" --list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 17 ]
    [[ "$output" == *"install_cert.sh"* ]]
    [[ "$output" == *"system_health_snapshot.sh"* ]]
    [[ "$output" == *"platform_check.sh"* ]]
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
